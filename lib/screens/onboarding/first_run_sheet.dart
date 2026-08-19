import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../providers/payment/payment_method_providers.dart';
import '../../services/storage/hive_service.dart' show kLocalPrefsBox;
import '../../utils/amount_expression.dart';
import '../../widgets/common/form_bits.dart';
import '../../widgets/common/salary_day_picker.dart';
import '../settings/providers/settings_providers.dart';

/// Shown once per account, straight after sign-in.
///
/// Keyed by user id rather than by device: onboarding completion is
/// device-level, so a second account signing in on the same phone would
/// otherwise never be asked anything and land on an empty dashboard.
String _seenKey(String userId) => 'firstRunDone:$userId';

bool firstRunDone(String userId) =>
    Hive.isBoxOpen(kLocalPrefsBox) &&
    Hive.box(kLocalPrefsBox).get(_seenKey(userId)) == true;

Future<void> markFirstRunDone(String userId) async {
  if (!Hive.isBoxOpen(kLocalPrefsBox)) return;
  await Hive.box(kLocalPrefsBox).put(_seenKey(userId), true);
}

/// One sheet, not a wizard: a multi-step flow at this moment gets skipped, and
/// everything here is optional anyway — whatever is left over shows up on the
/// dashboard checklist instead of being lost in Settings.
Future<void> showFirstRunSheet(BuildContext context, String userId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(top: false, child: FirstRunForm(userId: userId)),
    ),
  );
}

/// Public so the design harness can render it without driving a modal route.
class FirstRunForm extends ConsumerStatefulWidget {
  final String userId;

  const FirstRunForm({super.key, required this.userId});

  @override
  ConsumerState<FirstRunForm> createState() => _FirstRunFormState();
}

class _FirstRunFormState extends ConsumerState<FirstRunForm> {
  final _budget = TextEditingController();
  final _salary = TextEditingController();
  String? _method;
  bool _moveCycleStart = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _method = ref.read(defaultPaymentMethodProvider);
  }

  @override
  void dispose() {
    _budget.dispose();
    _salary.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool save}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (save) {
        final settings = ref.read(settingsProvider.notifier);
        final budget = parseAmountExpression(_budget.text.trim()) ?? 0;
        if (budget > 0) await settings.setCycleBudget(budget);
        final salary = parseAmountExpression(_salary.text.trim()) ?? 0;
        if (salary > 0) await settings.setCycleSalary(salary);
        if (_method != null) {
          await ref.read(paymentMethodsProvider.notifier).setDefault(_method);
        }
        // Only when they told us a day AND agreed: moving the cycle start
        // re-scopes every total on the dashboard, so it is never silent.
        final day = ref.read(settingsProvider).salaryDay;
        if (day != null && _moveCycleStart) {
          await settings.resetSalaryCycle(
            startDate: lastSalaryDayOnOrBefore(DateTime.now(), day),
          );
        }
      }
      await markFirstRunDone(widget.userId);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final salaryDay = ref.watch(settingsProvider.select((s) => s.salaryDay));
    final methods = ref.watch(paymentMethodsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
            'Set up your cycle',
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Three answers and the home screen starts telling you something. '
            'Skip any of them — you can finish from the dashboard later.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          const FieldLabel('MONTHLY BUDGET'),
          const SizedBox(height: 6),
          _AmountField(controller: _budget, hint: 'What you plan to spend'),
          const SizedBox(height: 18),
          const FieldLabel('SALARY'),
          const SizedBox(height: 6),
          _AmountField(controller: _salary, hint: 'What lands each month'),
          const SizedBox(height: 18),
          const FieldLabel('SALARY DAY'),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => pickSalaryDay(context, ref),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A21),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      salaryDay == null
                          ? 'Not set — the cycle starts on the 1st'
                          : 'The ${_ordinal(salaryDay)} of each month',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: salaryDay == null
                            ? cs.onSurfaceVariant
                            : cs.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: cs.outline,
                  ),
                ],
              ),
            ),
          ),
          if (salaryDay != null) ...[
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _moveCycleStart,
              onChanged: (v) => setState(() => _moveCycleStart = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                'Start this cycle on the '
                '${_ordinal(lastSalaryDayOnOrBefore(DateTime.now(), salaryDay).day)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const FieldLabel('PAID VIA, USUALLY'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: methods
                .map(
                  (m) => ChoicePill(
                    label: m,
                    selected: _method == m,
                    onTap: () =>
                        setState(() => _method = _method == m ? null : m),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6),
          Text(
            'Preselected on every expense, so you only change it when it '
            'differs.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(
                onPressed: _saving ? null : () => _finish(save: false),
                child: const Text('Skip for now'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientButton(
                  label: 'Save',
                  enabled: !_saving,
                  onPressed: () => _finish(save: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _AmountField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        prefixText: '₹ ',
        hintText: hint,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

String _ordinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}
