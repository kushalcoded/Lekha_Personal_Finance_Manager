import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../providers/auth/auth_provider.dart';
import '../../../providers/budget/budget_providers.dart';
import '../../../providers/payment/payment_method_providers.dart';
import '../../../services/storage/hive_service.dart' show kLocalPrefsBox;
import '../../../widgets/common/form_bits.dart';
import '../../../widgets/common/glass.dart';
import '../../../widgets/common/salary_day_picker.dart';
import '../../settings/providers/settings_providers.dart';
import '../../settings/widgets/manage_categories_screen.dart';
import '../../settings/widgets/manage_payment_methods_screen.dart';
import '../../settings/widgets/manage_people_screen.dart';
import 'budget_settings_modal.dart';

/// One thing a new account still hasn't been asked.
enum SetupStep { budget, salary, salaryDay, paymentMethod, categories, people }

extension SetupStepCopy on SetupStep {
  String get label => switch (this) {
    SetupStep.budget => 'Set a monthly budget',
    SetupStep.salary => 'Add your salary',
    SetupStep.salaryDay => 'Say when salary lands',
    SetupStep.paymentMethod => 'Pick a default payment method',
    SetupStep.categories => 'Make the categories yours',
    SetupStep.people => 'Add people you split with',
  };

  String get why => switch (this) {
    SetupStep.budget => 'The home screen has nothing to measure against',
    SetupStep.salary => 'Needed to work out what you actually keep',
    SetupStep.salaryDay => 'Otherwise every cycle starts on the 1st',
    SetupStep.paymentMethod => 'Every expense asks you to pick one',
    SetupStep.categories => 'Rename, restyle or add your own',
    SetupStep.people => 'Pin the ones you split with most',
  };
}

/// What a new account still has to be asked. Derived from real settings rather
/// than a stored wizard position, so a step ticks itself off however the user
/// got there — through this card, through Settings, or through the sheet after
/// sign-in.
///
/// Categories and people ship with working defaults, so there is nothing to
/// detect; they stay until opened once, which is honest about them being
/// discoverability rather than setup.
List<SetupStep> setupSteps({
  required double budget,
  required double salary,
  required int? salaryDay,
  required String? defaultPaymentMethod,
  required bool seenCategories,
  required bool seenPeople,
}) {
  return [
    if (budget <= 0) SetupStep.budget,
    if (salary <= 0) SetupStep.salary,
    if (salaryDay == null) SetupStep.salaryDay,
    if (defaultPaymentMethod == null || defaultPaymentMethod.trim().isEmpty)
      SetupStep.paymentMethod,
    if (!seenCategories) SetupStep.categories,
    if (!seenPeople) SetupStep.people,
  ];
}

/// Device-local: a checklist is about this person on this screen, and syncing
/// "I opened Categories once" between devices isn't worth a settings key.
const _dismissedKey = 'setupChecklistDismissed';
const _seenCategoriesKey = 'setupSeenCategories';
const _seenPeopleKey = 'setupSeenPeople';

bool _flag(String key) =>
    Hive.isBoxOpen(kLocalPrefsBox) && Hive.box(kLocalPrefsBox).get(key) == true;

Future<void> _setFlag(String key) async {
  if (!Hive.isBoxOpen(kLocalPrefsBox)) return;
  await Hive.box(kLocalPrefsBox).put(key, true);
}

/// "Finish setting up" — the things a new account can't find, on the screen it
/// lands on. All of it is otherwise buried in Settings, which is where new
/// users were losing the budget, the salary and the default payment method.
class SetupChecklistCard extends ConsumerStatefulWidget {
  const SetupChecklistCard({super.key});

  @override
  ConsumerState<SetupChecklistCard> createState() => _SetupChecklistCardState();
}

class _SetupChecklistCardState extends ConsumerState<SetupChecklistCard> {
  @override
  Widget build(BuildContext context) {
    if (_flag(_dismissedKey)) return const SizedBox.shrink();

    final userId = ref.watch(currentUserIdProvider) ?? '';
    final settings = ref.watch(settingsProvider);
    final metrics = ref.watch(budgetMetricsProvider(userId));
    final steps = setupSteps(
      budget: metrics.budget,
      salary: metrics.salary,
      salaryDay: settings.salaryDay,
      defaultPaymentMethod: ref.watch(defaultPaymentMethodProvider),
      seenCategories: _flag(_seenCategoriesKey),
      seenPeople: _flag(_seenPeopleKey),
    );
    if (steps.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AccentEdgeCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: FieldLabel('FINISH SETTING UP')),
                Text(
                  '${steps.length} left',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final step in steps) ...[
              if (step != steps.first) const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _open(step),
                child: Row(
                  children: [
                    Icon(
                      Icons.radio_button_unchecked_rounded,
                      size: 15,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            step.why,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
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
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await _setFlag(_dismissedKey);
                  if (mounted) setState(() {});
                },
                child: const Text('Dismiss'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(SetupStep step) async {
    switch (step) {
      case SetupStep.budget:
        await showBudgetSettingsModal(context);
      case SetupStep.salary:
        await showSalarySettingsModal(context);
      case SetupStep.salaryDay:
        await pickSalaryDay(context, ref);
      case SetupStep.paymentMethod:
        await _push(const ManagePaymentMethodsScreen());
      case SetupStep.categories:
        await _setFlag(_seenCategoriesKey);
        await _push(const ManageCategoriesScreen());
      case SetupStep.people:
        await _setFlag(_seenPeopleKey);
        await _push(const ManagePeopleScreen());
    }
    // The derived steps come back through providers on rebuild; the
    // tapped-once flags live in Hive, which nothing is watching.
    if (mounted) setState(() {});
  }

  Future<void> _push(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));
}
