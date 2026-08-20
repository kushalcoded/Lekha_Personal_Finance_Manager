import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/payable/payable_model.dart';
import '../../../models/receivable/receivable_model.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/people/people_providers.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../../utils/amount_expression.dart';
import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/form_bits.dart';
import '../../../widgets/common/person_menu.dart';
import '../../../widgets/responsive/responsive_sheet.dart';
import '../../expenses/widgets/amount_input.dart';
import '../../expenses/widgets/expense_date_picker.dart';
import '../../expenses/widgets/expense_notes_field.dart';
import '../../expenses/widgets/save_expense_button.dart';

/// Who the money came from. The ledger has no direction of its own — it is a
/// receivable or a payable — so this is the one thing the form has to ask.
enum DebtDirection { youPaid, theyPaid }

/// The amount and the store a new debt belongs in, or null while the amount
/// isn't yet a positive number.
///
/// Pure, because the whole rule is one easily-inverted sentence: money that
/// left your pocket is money they owe you.
({bool receivable, double amount})? resolveDebtDraft({
  required DebtDirection direction,
  required String rawAmount,
}) {
  final amount = parseAmountExpression(rawAmount.trim());
  if (amount == null || amount <= 0) return null;
  return (receivable: direction == DebtDirection.youPaid, amount: amount);
}

/// The sentence shown under the direction pills. Spelling the outcome out is
/// cheaper than making someone reason about "payable" vs "receivable".
String debtSummaryLine({
  required String name,
  required double amount,
  required DebtDirection direction,
}) {
  final money = AppFormatters.formatCurrency(amount);
  return direction == DebtDirection.youPaid
      ? '$name will owe you $money'
      : "You'll owe $name $money";
}

/// Add a debt in one sheet: amount, who with, which way round.
///
/// Replaces the old two-step flow, which made you declare the direction in a
/// chooser *before* it would show you a form — so the first tap happened
/// before you had typed anything at all.
Future<void> showAddDebtSheet(BuildContext context, {String? person}) {
  return showResponsiveSheet(
    context,
    mobileChild: AddDebtForm(person: person),
    desktopChild: AddDebtForm(person: person),
  );
}

class AddDebtForm extends ConsumerStatefulWidget {
  /// Prefilled when the sheet is opened from someone's ledger.
  final String? person;

  const AddDebtForm({super.key, this.person});

  @override
  ConsumerState<AddDebtForm> createState() => _AddDebtFormState();
}

class _AddDebtFormState extends ConsumerState<AddDebtForm> {
  final _amount = TextEditingController();
  late final TextEditingController _name;
  final _note = TextEditingController();

  DebtDirection _direction = DebtDirection.youPaid;
  DateTime _dueDate = DateTime.now();
  bool _showMore = false;
  bool _showValidation = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.person ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  void _markInteracted() {
    if (!_showValidation) setState(() => _showValidation = true);
  }

  /// Tapping a pill is a decision, not typing — drop the keyboard so the save
  /// button isn't left hiding behind it.
  void _chose(VoidCallback change) {
    FocusScope.of(context).unfocus();
    _markInteracted();
    setState(change);
  }

  void _pickName(String name) => _chose(() {
    _name.text = name;
  });

  Future<void> _save() async {
    final draft = resolveDebtDraft(
      direction: _direction,
      rawAmount: _amount.text,
    );
    final name = _name.text.trim();
    if (draft == null || name.isEmpty) {
      setState(() => _showValidation = true);
      return;
    }

    setState(() => _saving = true);
    final userId = ref.read(currentUserIdProvider) ?? localUserId;
    final now = DateTime.now();
    final note = _note.text.trim();

    try {
      if (draft.receivable) {
        await ref
            .read(receivablesProvider.notifier)
            .addReceivable(
              Receivable(
                id: const Uuid().v4(),
                userId: userId,
                fromPerson: name,
                amount: draft.amount,
                description: note.isEmpty ? null : note,
                dueDate: _dueDate,
                isPaid: false,
                createdAt: now,
              ),
            );
      } else {
        await ref
            .read(payablesProvider.notifier)
            .addPayable(
              Payable(
                id: const Uuid().v4(),
                userId: userId,
                toPerson: name,
                amount: draft.amount,
                remainingAmount: draft.amount,
                // A hand-entered debt has no bill behind it to categorise, and
                // Payable.fromJson already falls back to this same value.
                category: 'Miscellaneous',
                notes: note.isEmpty ? null : note,
                createdAt: now,
                dueDate: _dueDate,
                status: PayableStatus.pending,
                settlements: const [],
              ),
            );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            debtSummaryLine(
              name: name,
              amount: draft.amount,
              direction: _direction,
            ),
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save the debt: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final prefs = ref.watch(peoplePrefsProvider);
    final known = ref.watch(knownPeopleProvider);
    final draft = resolveDebtDraft(
      direction: _direction,
      rawAmount: _amount.text,
    );
    final name = _name.text.trim();
    final canSave = draft != null && name.isNotEmpty && !_saving;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                Text(
                  'Add a debt',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Money lent or borrowed on its own. A shared bill is better '
                  'added as an expense and split.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                const FieldLabel('AMOUNT'),
                const SizedBox(height: 6),
                AmountInput(
                  controller: _amount,
                  onChanged: (_) => setState(_markInteracted),
                  showError: _showValidation && draft == null,
                ),
                const SizedBox(height: 18),
                const FieldLabel('WITH'),
                const SizedBox(height: 6),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(_markInteracted),
                  decoration: InputDecoration(
                    hintText: 'Who is this with?',
                    prefixIcon: const Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                    ),
                    errorText: _showValidation && name.isEmpty
                        ? 'Add a name'
                        : null,
                  ),
                ),
                if (known.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: known
                        .map(
                          (n) => GestureDetector(
                            onLongPress: () => showPersonMenu(
                              context,
                              ref,
                              n,
                              isPinned: prefs.isPinned(n),
                            ),
                            child: ChoicePill(
                              label: n,
                              icon: prefs.isPinned(n)
                                  ? Icons.push_pin_rounded
                                  : null,
                              selected: n.toLowerCase() == name.toLowerCase(),
                              onTap: () => _pickName(n),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 18),
                const FieldLabel('WHO PAID'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoicePill(
                      label: 'You paid',
                      selected: _direction == DebtDirection.youPaid,
                      onTap: () =>
                          _chose(() => _direction = DebtDirection.youPaid),
                    ),
                    ChoicePill(
                      label: 'They paid',
                      selected: _direction == DebtDirection.theyPaid,
                      onTap: () =>
                          _chose(() => _direction = DebtDirection.theyPaid),
                    ),
                  ],
                ),
                if (draft != null && name.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    debtSummaryLine(
                      name: name,
                      amount: draft.amount,
                      direction: _direction,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _chose(() => _showMore = !_showMore),
                    icon: Icon(
                      _showMore
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                    ),
                    label: Text(_showMore ? 'Less' : 'Note and due date'),
                  ),
                ),
                if (_showMore) ...[
                  const SizedBox(height: 4),
                  const FieldLabel('DUE'),
                  const SizedBox(height: 6),
                  ExpenseDatePicker(
                    selectedDate: _dueDate,
                    onChanged: (d) => _chose(() => _dueDate = d),
                  ),
                  const SizedBox(height: 14),
                  const FieldLabel('NOTE'),
                  const SizedBox(height: 6),
                  ExpenseNotesField(
                    controller: _note,
                    onChanged: (_) => _markInteracted(),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Pinned: with the keyboard up and a row of name pills, a save button
        // that scrolls away is the reason the old form needed the keyboard
        // dismissed before it could be submitted.
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: SaveExpenseButton(
            label: _saving ? 'Saving…' : 'Add debt',
            isEnabled: canSave,
            onPressed: _save,
          ),
        ),
      ],
    );
  }
}
