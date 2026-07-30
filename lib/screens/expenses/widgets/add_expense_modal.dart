import '../../../utils/amount_expression.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/category_styles.dart';
import '../../../models/expense/expense_model.dart';
import '../../../providers/ai_providers.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/cycle/cycle_providers.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../../utils/formatters/formatters.dart';
import '../providers/expenses_providers.dart';
import '../utils/expense_helpers.dart';
import '../utils/split_helpers.dart';
import '../utils/split_persistence.dart';
import '../../../widgets/common/form_bits.dart';
import 'expense_notes_field.dart';
import 'split_sheet.dart';

Future<void> showAddExpenseModal(
  BuildContext context, {
  bool autoStartVoice = false,
  double? initialAmount,
  DateTime? initialDate,
  void Function(Expense expense)? onSaved,
}) {
  final isDesktop = MediaQuery.of(context).size.width >= 900;

  if (isDesktop) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AddExpenseForm(
              isDialog: true,
              autoStartVoice: autoStartVoice,
              initialAmount: initialAmount,
              initialDate: initialDate,
              onSaved: onSaved,
            ),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: AddExpenseForm(
            isDialog: false,
            autoStartVoice: autoStartVoice,
            initialAmount: initialAmount,
            initialDate: initialDate,
            onSaved: onSaved,
          ),
        ),
      );
    },
  );
}

class AddExpenseForm extends ConsumerStatefulWidget {
  final bool isDialog;
  final bool autoStartVoice;
  final double? initialAmount;
  final DateTime? initialDate;
  final void Function(Expense expense)? onSaved;

  const AddExpenseForm({
    super.key,
    required this.isDialog,
    this.autoStartVoice = false,
    this.initialAmount,
    this.initialDate,
    this.onSaved,
  });

  @override
  ConsumerState<AddExpenseForm> createState() => _AddExpenseFormState();
}

class _AddExpenseFormState extends ConsumerState<AddExpenseForm> {
  static const List<String> _paymentMethods = [
    'Cash',
    'GPay',
    'PhonePe',
    'Paytm',
    'Bank Transfer',
    'Card',
  ];

  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _nlController = TextEditingController();
  final SpeechToText _speech = SpeechToText();

  String? _selectedCategory;
  String? _selectedPaymentMethod;
  DateTime _selectedDate = DateTime.now();
  SplitConfig _split = const SplitConfig();
  bool _showValidation = false;
  bool _suggestingCategory = false;
  bool _parsing = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    // Prefill from a detected SMS transaction (amount + date).
    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      final a = widget.initialAmount!;
      _amountController.text = a % 1 == 0 ? a.toInt().toString() : a.toString();
      _showValidation = true;
    }
    if (widget.initialDate != null) _selectedDate = widget.initialDate!;
    // Opened from the home-screen widget's mic button: start dictation.
    if (widget.autoStartVoice && ref.read(geminiConfiguredProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toggleListen();
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _nlController.dispose();
    _speech.stop();
    super.dispose();
  }

  /// Feature 2: parse the free-text/voice phrase into the form fields.
  Future<void> _parseNl() async {
    final text = _nlController.text.trim();
    if (text.isEmpty) return;
    setState(() => _parsing = true);
    try {
      final result = await ref
          .read(geminiServiceProvider)
          .parseExpenseFromText(
            text: text,
            categories: ref.read(expenseCategoriesProvider),
            paymentMethods: _paymentMethods,
            todayIso: DateTime.now().toIso8601String().split('T').first,
          );
      _applyParsed(result);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not understand that. Try rephrasing.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  void _applyParsed(Map<String, dynamic> parsed) {
    final categories = ref.read(expenseCategoriesProvider);
    final amount = (parsed['amount'] as num?)?.toDouble() ?? 0;
    final category = (parsed['category'] as String? ?? '').trim();
    final note = (parsed['note'] as String? ?? '').trim();
    final dateStr = (parsed['date'] as String? ?? '').trim();
    final method = (parsed['paymentMethod'] as String? ?? '').trim();
    String pick(List<String> options, String value) => options.firstWhere(
      (o) => o.toLowerCase() == value.toLowerCase(),
      orElse: () => '',
    );
    setState(() {
      if (amount > 0) {
        _amountController.text = amount % 1 == 0
            ? amount.toInt().toString()
            : amount.toString();
      }
      final cat = pick(categories, category);
      if (cat.isNotEmpty) _selectedCategory = cat;
      if (note.isNotEmpty) _notesController.text = note;
      final parsedDate = DateTime.tryParse(dateStr);
      if (parsedDate != null) _selectedDate = parsedDate;
      final methodMatch = pick(_paymentMethods, method);
      if (methodMatch.isNotEmpty) _selectedPaymentMethod = methodMatch;
      _showValidation = true;
    });
  }

  /// Feature 2: dictate the quick-add phrase; auto-parses on the final result.
  Future<void> _toggleListen() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize();
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition unavailable.')),
        );
      }
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        setState(() => _nlController.text = result.recognizedWords);
        if (result.finalResult) {
          setState(() => _listening = false);
          _parseNl();
        }
      },
    );
  }

  bool get _isAmountValid {
    final text = _amountController.text.trim();
    final value = parseAmountExpression(text);
    return value != null && value > 0;
  }

  bool get _isFormValid {
    return _isAmountValid &&
        _selectedCategory != null &&
        _selectedPaymentMethod != null;
  }

  void _markInteracted() {
    if (!_showValidation) {
      setState(() => _showValidation = true);
    }
  }

  /// Feature 1: ask Gemini to pick a category from the notes/amount.
  Future<void> _suggestCategory() async {
    final categories = ref.read(expenseCategoriesProvider);
    final notes = _notesController.text.trim();
    if (notes.isEmpty) return;
    setState(() => _suggestingCategory = true);
    try {
      final suggestion = await ref
          .read(geminiServiceProvider)
          .suggestExpenseCategory(
            categories: categories,
            notes: notes,
            amount: parseAmountExpression(_amountController.text.trim()),
          );
      final match = categories.firstWhere(
        (c) => c.toLowerCase() == suggestion.trim().toLowerCase(),
        orElse: () => '',
      );
      if (match.isNotEmpty) {
        setState(() => _selectedCategory = match);
      }
    } catch (_) {
      // Offline / not configured / bad response: leave selection untouched.
    } finally {
      if (mounted) setState(() => _suggestingCategory = false);
    }
  }

  /// Feature 5: local duplicate/anomaly check; if flagged, confirm before
  /// saving. Warning text comes from Gemini when configured, local otherwise.
  Future<bool> _confirmIfWarned(
    String userId,
    double amount,
    String category,
    DateTime date,
  ) async {
    final cycleExpenses = ref
        .read(cycleExpensesProvider)
        .where((e) => e.userId == userId)
        .toList();
    final warning = detectExpenseWarning(
      amount: amount,
      category: category,
      date: date,
      cycleExpenses: cycleExpenses,
    );
    if (warning.kind == ExpenseWarningKind.none) return true;

    final message = await _warningMessage(warning);
    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          warning.kind == ExpenseWarningKind.duplicate
              ? 'Possible duplicate'
              : 'Unusually high',
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add anyway'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  Future<String> _warningMessage(ExpenseWarning warning) async {
    final local = warning.kind == ExpenseWarningKind.duplicate
        ? 'This looks like a duplicate of a ${warning.category} expense you '
              'already added today.'
        : 'This ${warning.category} expense is much higher than your usual '
              'spend this cycle.';
    final service = ref.read(geminiServiceProvider);
    if (!service.isConfigured) return local;
    try {
      return await service.explainSpendingWarning(
        kind: warning.kind.name,
        category: warning.category,
        amount: warning.amount,
        typical: warning.typical,
      );
    } catch (_) {
      return local;
    }
  }

  /// Short marker for the expense row — the stored amount is only your share,
  /// so we note the real bill but keep it terse. The names live on the debts.
  String? _expenseNote(double total) {
    final typed = _notesController.text.trim();
    if (!_split.isActive) return typed.isEmpty ? null : typed;
    final amount = AppFormatters.formatCurrency(total);
    return typed.isEmpty ? 'Split $amount' : '$typed · Split $amount';
  }

  void _handleSave() async {
    if (!_isFormValid) {
      setState(() => _showValidation = true);
      return;
    }

    final userId = ref.read(currentUserIdProvider) ?? localUserId;
    final total = (parseAmountExpression(_amountController.text.trim()) ?? 0);

    // When the bill is split, the expense is only what YOU consumed — the rest
    // is money you're owed (or owe), not spending.
    final split = _split.isActive ? _splitResult : null;
    final amount = split?.myShare ?? total;
    final note = _expenseNote(total);

    if (!await _confirmIfWarned(
      userId,
      amount,
      _selectedCategory!,
      _selectedDate,
    )) {
      return;
    }
    if (!mounted) return;

    final expense = Expense(
      id: const Uuid().v4(),
      userId: userId,
      amount: amount,
      category: _selectedCategory!,
      description: note,
      date: _selectedDate,
      paymentMethod: _selectedPaymentMethod,
      createdAt: DateTime.now(),
      updatedAt: null,
    );

    try {
      await ref.read(expensesProvider.notifier).addExpense(expense);
      // Same short note as the expense: what it was for + the real bill. The
      // person's name is already the ledger you're looking at, so no names.
      if (split != null) {
        await createSplitDebts(
          ref: ref,
          userId: userId,
          sourceExpenseId: expense.id,
          config: _split,
          split: split,
          note: note,
          date: _selectedDate,
          category: _selectedCategory!,
        );
      }
      widget.onSaved?.call(expense);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense saved successfully'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving expense: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Local, synchronous heads-up shown inline as the user fills the form.
  /// The AI-worded version still appears in the confirm dialog on save.
  String? _inlineWarning() {
    if (!_isAmountValid || _selectedCategory == null) return null;
    final userId = ref.read(currentUserIdProvider) ?? localUserId;
    final amount = (parseAmountExpression(_amountController.text.trim()) ?? 0);
    final cycleExpenses = ref
        .read(cycleExpensesProvider)
        .where((e) => e.userId == userId)
        .toList();
    final warning = detectExpenseWarning(
      amount: amount,
      category: _selectedCategory!,
      date: _selectedDate,
      cycleExpenses: cycleExpenses,
    );
    return switch (warning.kind) {
      ExpenseWarningKind.duplicate =>
        'Looks like a duplicate of a ${warning.category} expense you already '
            'added today.',
      ExpenseWarningKind.anomaly =>
        'This ${warning.category} expense is much higher than your usual spend '
            'this cycle.',
      ExpenseWarningKind.none => null,
    };
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) {
      _markInteracted();
      setState(() => _selectedDate = picked);
    }
  }

  String _formatShortDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  /// Violet natural-language quick-add bar: type or dictate a phrase, then
  /// parse it into the fields below (features 1 & 2).
  Widget _nlQuickAdd(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _nlController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _parseNl(),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: '"420 groceries yesterday on gpay"',
              ),
            ),
          ),
          const SizedBox(width: 8),
          _nlIcon(
            cs,
            icon: _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
            active: _listening,
            onTap: _toggleListen,
          ),
          const SizedBox(width: 6),
          _parsing
              ? const Padding(
                  padding: EdgeInsets.all(7),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _nlIcon(
                  cs,
                  icon: Icons.auto_awesome_rounded,
                  active: false,
                  onTap: _parseNl,
                ),
        ],
      ),
    );
  }

  Widget _nlIcon(
    ColorScheme cs, {
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: active ? cs.error : cs.primary),
      ),
    );
  }

  Widget _amountBox(ThemeData theme, ColorScheme cs) {
    final err = _showValidation && !_isAmountValid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF221E2C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: err ? cs.error : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Text(
            '₹',
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: '0',
              ),
              onChanged: (_) {
                _markInteracted();
                setState(() {});
              },
            ),
          ),
          // Calculator entry ('450+89', '450, 89') shows its total live.
          if (isMultiTermAmount(_amountController.text))
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '= ${AppFormatters.formatCurrency(_total)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  double get _total =>
      parseAmountExpression(_amountController.text.trim()) ?? 0;

  /// Shares for the current bill total — recomputed each build so editing the
  /// amount after configuring a split stays correct.
  SplitResult get _splitResult => computeSplit(
    total: _total,
    people: _split.people,
    mode: _split.mode,
    exactAmounts: _split.exact,
  );

  Future<void> _openSplit() async {
    if (_total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the total amount first')),
      );
      return;
    }
    final result = await showSplitSheet(
      context,
      total: _total,
      initial: _split,
    );
    if (result != null && mounted) setState(() => _split = result);
  }

  Widget _splitRow(ThemeData theme, ColorScheme cs) {
    if (!_split.isActive) {
      return InkWell(
        onTap: _openSplit,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF221E2C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Icon(Icons.call_split_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Split this bill',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      );
    }

    final result = _splitResult;
    final sub = _split.paidByMe
        ? '${AppFormatters.formatCurrency(result.othersTotal)} to receivables'
        : 'you owe ${_split.paidBy}';

    return InkWell(
      onTap: _openSplit,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(Icons.call_split_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Split with ${_split.people.join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your share ${AppFormatters.formatCurrency(result.myShare)} · $sub',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_rounded, size: 15, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _suggestLink(ColorScheme cs) {
    return InkWell(
      onTap: _suggestingCategory ? null : _suggestCategory,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _suggestingCategory
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.auto_awesome_rounded, size: 14, color: cs.primary),
          const SizedBox(width: 5),
          Text(
            'Suggest from notes',
            style: TextStyle(
              fontSize: 11.5,
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final aiConfigured = ref.watch(geminiConfiguredProvider);
    final categories = ref.watch(expenseCategoriesProvider);
    final inlineWarning = _inlineWarning();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, widget.isDialog ? 20 : 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.isDialog)
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Add expense',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                InkResponse(
                  onTap: () => Navigator.of(context).pop(),
                  radius: 22,
                  child: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (aiConfigured) ...[_nlQuickAdd(cs), const SizedBox(height: 18)],
            const FieldLabel('Amount'),
            const SizedBox(height: 8),
            _amountBox(theme, cs),
            const SizedBox(height: 18),
            const FieldLabel('Note'),
            const SizedBox(height: 8),
            ExpenseNotesField(
              controller: _notesController,
              onChanged: (_) => _markInteracted(),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const FieldLabel('Category'),
                const Spacer(),
                if (aiConfigured) _suggestLink(cs),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categories.map((c) {
                final style = CategoryStyles.of(c);
                return ChoicePill(
                  label: c,
                  dotColor: style.color,
                  selected: _selectedCategory == c,
                  onTap: () {
                    _markInteracted();
                    setState(() => _selectedCategory = c);
                  },
                );
              }).toList(),
            ),
            if (_showValidation && _selectedCategory == null) ...[
              const SizedBox(height: 6),
              Text(
                'Select a category',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            const SizedBox(height: 18),
            const FieldLabel('Payment · Date'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._paymentMethods.map(
                  (m) => ChoicePill(
                    label: m,
                    selected: _selectedPaymentMethod == m,
                    onTap: () {
                      _markInteracted();
                      setState(() => _selectedPaymentMethod = m);
                    },
                  ),
                ),
                ChoicePill(
                  label: _formatShortDate(_selectedDate),
                  icon: Icons.calendar_today_rounded,
                  selected: false,
                  onTap: _pickDate,
                ),
              ],
            ),
            if (_showValidation && _selectedPaymentMethod == null) ...[
              const SizedBox(height: 6),
              Text(
                'Select a payment method',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            const SizedBox(height: 18),
            const FieldLabel('Split'),
            const SizedBox(height: 8),
            _splitRow(theme, cs),
            if (inlineWarning != null) ...[
              const SizedBox(height: 16),
              _WarnBanner(text: inlineWarning),
            ],
            const SizedBox(height: 22),
            if (widget.isDialog)
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: 'Add expense',
                      enabled: _isFormValid,
                      onPressed: _handleSave,
                    ),
                  ),
                ],
              )
            else
              GradientButton(
                label: 'Add expense',
                enabled: _isFormValid,
                onPressed: _handleSave,
              ),
          ],
        ),
      ),
    );
  }
}

/// Amber inline warning banner for a possible duplicate / unusual amount.
class _WarnBanner extends StatelessWidget {
  final String text;

  const _WarnBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    const warn = Color(0xFFD7A24C);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: warn.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 17, color: warn),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFE4D3B4),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
