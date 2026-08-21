import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth/auth_provider.dart';
import '../../../providers/share/share_providers.dart';
import '../../../utils/amount_expression.dart';
import '../../../widgets/common/form_bits.dart';
import '../../../widgets/responsive/responsive_sheet.dart';
import '../../expenses/widgets/amount_input.dart';
import '../../expenses/widgets/expense_date_picker.dart';
import '../../expenses/widgets/expense_notes_field.dart';
import '../../expenses/widgets/save_expense_button.dart';
import '../../settings/providers/settings_providers.dart';

/// Add an expense to a group from the app.
///
/// Same three questions the guest page asks — how much, who paid, who was in
/// it — because the owner is a participant like everyone else, not an approver
/// standing outside it. Without this they could only accept what guests
/// submitted, which is not managing a group.
Future<void> showGroupExpenseSheet(BuildContext context, SharedGroup group) {
  return showResponsiveSheet(
    context,
    mobileChild: _GroupExpenseForm(group: group),
    desktopChild: _GroupExpenseForm(group: group),
  );
}

class _GroupExpenseForm extends ConsumerStatefulWidget {
  final SharedGroup group;

  const _GroupExpenseForm({required this.group});

  @override
  ConsumerState<_GroupExpenseForm> createState() => _GroupExpenseFormState();
}

class _GroupExpenseFormState extends ConsumerState<_GroupExpenseForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String _payer = '';
  List<String> _with = const [];
  bool _showValidation = false;
  bool _saving = false;
  String? _error;

  String get _me => ref.read(settingsProvider).displayName.trim();

  List<String> get _everyone => [
    _me,
    ...widget.group.members.map((m) => m.name),
  ];

  @override
  void initState() {
    super.initState();
    _payer = ref.read(settingsProvider).displayName.trim();
    _with = _everyone;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _choose(VoidCallback change) {
    FocusScope.of(context).unfocus();
    setState(change);
  }

  /// Equal among whoever is ticked, with the rounding remainder left on the
  /// last of them rather than quietly lost.
  Map<String, double> _shares(double total) {
    final each = (total / _with.length * 100).round() / 100;
    final shares = <String, double>{};
    var running = 0.0;
    for (var i = 0; i < _with.length; i++) {
      final amount = i == _with.length - 1
          ? ((total - running) * 100).round() / 100
          : each;
      running += amount;
      if (amount > 0) shares[_with[i]] = amount;
    }
    return shares;
  }

  Future<void> _save() async {
    final total = parseAmountExpression(_amount.text.trim()) ?? 0;
    if (total <= 0 || _with.isEmpty) {
      setState(() => _showValidation = true);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await addGroupEntry(
        ref: ref,
        group: widget.group,
        userId: ref.read(currentUserIdProvider) ?? localUserId,
        ownerName: _me,
        total: total,
        payerName: _payer,
        shares: _shares(total),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        date: _date,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not add that: $e';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(const SnackBar(content: Text('Added to the group')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = parseAmountExpression(_amount.text.trim()) ?? 0;
    final everyone = _everyone;

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
                Text(
                  'Add to ${widget.group.title}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Everyone on the group sees this straight away.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                const FieldLabel('AMOUNT'),
                const SizedBox(height: 6),
                AmountInput(
                  controller: _amount,
                  onChanged: (_) => setState(() {}),
                  showError: _showValidation && total <= 0,
                ),
                const SizedBox(height: 18),
                const FieldLabel('WHAT FOR'),
                const SizedBox(height: 6),
                ExpenseNotesField(controller: _note, onChanged: (_) {}),
                const SizedBox(height: 18),
                const FieldLabel('WHEN'),
                const SizedBox(height: 6),
                ExpenseDatePicker(
                  selectedDate: _date,
                  onChanged: (d) => _choose(() => _date = d),
                ),
                const SizedBox(height: 18),
                const FieldLabel('WHO PAID'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: everyone
                      .map(
                        (name) => ChoicePill(
                          label: name == _me ? 'You' : name,
                          selected: _payer == name,
                          onTap: () => _choose(() => _payer = name),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 18),
                const FieldLabel('SPLIT BETWEEN'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: everyone
                      .map(
                        (name) => ChoicePill(
                          label: name == _me ? 'You' : name,
                          selected: _with.contains(name),
                          onTap: () => _choose(() {
                            if (_with.contains(name)) {
                              // Somebody has to be in it.
                              if (_with.length == 1) return;
                              _with = [..._with]..remove(name);
                            } else {
                              _with = [..._with, name];
                            }
                          }),
                        ),
                      )
                      .toList(),
                ),
                if (total > 0 && _with.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _with.length == 1
                        ? 'All of it on '
                              '${_with.single == _me ? 'you' : _with.single}'
                        : 'Split ${_with.length} ways',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                  ),
                ],
              ],
            ),
          ),
        ),
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
            label: _saving ? 'Adding…' : 'Add to group',
            isEnabled: total > 0 && _with.isNotEmpty && !_saving,
            onPressed: _save,
          ),
        ),
      ],
    );
  }
}
