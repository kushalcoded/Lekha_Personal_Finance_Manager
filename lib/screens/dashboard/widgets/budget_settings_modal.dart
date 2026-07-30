import '../../../utils/amount_expression.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth/auth_provider.dart';
import '../../../providers/budget/budget_providers.dart';
import '../../settings/providers/settings_providers.dart';

Future<void> showBudgetSettingsModal(BuildContext context) {
  return _showCycleAmountSettingsModal(
    context,
    amountType: _CycleAmountType.budget,
  );
}

Future<void> showSalarySettingsModal(BuildContext context) {
  return _showCycleAmountSettingsModal(
    context,
    amountType: _CycleAmountType.salary,
  );
}

Future<void> _showCycleAmountSettingsModal(
  BuildContext context, {
  required _CycleAmountType amountType,
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
            constraints: const BoxConstraints(maxWidth: 460),
            child: _CycleAmountSettingsForm(
              isDialog: true,
              amountType: amountType,
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: _CycleAmountSettingsForm(amountType: amountType),
        ),
      );
    },
  );
}

enum _CycleAmountType { budget, salary }

class _CycleAmountSettingsForm extends ConsumerStatefulWidget {
  final bool isDialog;
  final _CycleAmountType amountType;

  const _CycleAmountSettingsForm({
    this.isDialog = false,
    required this.amountType,
  });

  @override
  ConsumerState<_CycleAmountSettingsForm> createState() =>
      _CycleAmountSettingsFormState();
}

class _CycleAmountSettingsFormState
    extends ConsumerState<_CycleAmountSettingsForm> {
  final _budgetController = TextEditingController();
  bool _showValidation = false;

  @override
  void initState() {
    super.initState();
    final userId = ref.read(currentUserIdProvider) ?? '';
    final amount = widget.amountType == _CycleAmountType.budget
        ? ref.read(monthlyBudgetProvider(userId)).amount
        : ref.read(cycleSalaryProvider(userId)).amount;
    if (amount > 0) {
      _budgetController.text = amount.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
  }

  bool get _isValid {
    final value = parseAmountExpression(_budgetController.text.trim());
    return value != null && value > 0;
  }

  Future<void> _save() async {
    if (!_isValid) {
      setState(() => _showValidation = true);
      return;
    }

    final amount = (parseAmountExpression(_budgetController.text.trim()) ?? 0);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    if (widget.amountType == _CycleAmountType.budget) {
      await settingsNotifier.setCycleBudget(amount);
    } else {
      await settingsNotifier.setCycleSalary(amount);
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$_labelPrefix updated for the current cycle')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    if (widget.amountType == _CycleAmountType.budget) {
      await settingsNotifier.resetCycleBudget();
    } else {
      await settingsNotifier.resetCycleSalary();
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$_labelPrefix reset for the current cycle')),
    );
    Navigator.of(context).pop();
  }

  String get _labelPrefix =>
      widget.amountType == _CycleAmountType.budget ? 'Budget' : 'Salary';

  String get _description => widget.amountType == _CycleAmountType.budget
      ? 'Set the spending target for this cycle'
      : 'Set the income planned for this cycle';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outline.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cycle $_labelPrefix',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _budgetController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '$_labelPrefix amount',
                hintText: '0.00',
                prefixText: 'Rs ',
                errorText: _showValidation && !_isValid
                    ? 'Enter a valid ${_labelPrefix.toLowerCase()}'
                    : null,
              ),
              onChanged: (_) {
                if (!_showValidation) {
                  setState(() => _showValidation = true);
                } else {
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 20),
            if (widget.isDialog)
              Row(
                children: [
                  TextButton(onPressed: _reset, child: const Text('Reset')),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isValid ? _save : null,
                    child: Text('Save $_labelPrefix'),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: _isValid ? _save : null,
                    child: Text('Save $_labelPrefix'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _reset,
                    child: Text('Reset $_labelPrefix'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
