import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/category_styles.dart';
import '../../../models/category/expense_category.dart';
import '../../../models/recurring/recurring_expense_template.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/categories/category_providers.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/amount_expression.dart';
import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/form_bits.dart';
import '../../../widgets/common/glass.dart';
import '../../../widgets/common/top_notice.dart';
import '../../../widgets/responsive/responsive_sheet.dart';
import '../../expenses/providers/recurring_expenses_providers.dart';
import '../../expenses/widgets/amount_input.dart';
import '../../expenses/widgets/save_expense_button.dart';

/// The bills and SIPs waiting to be recorded, on the screen the user actually
/// opens.
///
/// Nothing in the app generates a recurring expense on its own — that is
/// deliberate, because a bill's real amount is often not the template's — but
/// until now the only way to record one was a button behind an app-bar icon on
/// another screen. So bills sat undone and the budget quietly lied.
///
/// Tapping **Paid** records the usual amount. Tapping the **amount** records a
/// different one, which is the whole answer to an electricity bill that is
/// never the same twice.
class BillsDueCard extends ConsumerWidget {
  const BillsDueCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final due = ref.watch(dueRecurringTemplatesProvider(userId));
    if (due.isEmpty) return const SizedBox.shrink();

    final sorted = [...due]
      ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Due now'),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final template in sorted)
                  _BillRow(key: ValueKey(template.id), template: template),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BillRow extends ConsumerWidget {
  final RecurringExpenseTemplate template;

  const _BillRow({super.key, required this.template});

  /// What this bill came to last time. Shown only when it differs from the
  /// template — on a fixed rent it is noise, on electricity it is the number
  /// you are about to compare against.
  double? _lastAmount(WidgetRef ref) {
    final id = template.lastGeneratedExpenseId;
    if (id == null) return null;
    for (final expense in ref.watch(expensesProvider).expenses) {
      if (expense.id == id) {
        return (expense.amount - template.amount).abs() < 0.01
            ? null
            : expense.amount;
      }
    }
    return null;
  }

  Future<void> _record(
    BuildContext context,
    WidgetRef ref, {
    double? amount,
  }) async {
    final before = template;
    final expenseId = await ref
        .read(recurringExpenseActionsProvider)
        .generateExpenseFromTemplate(template, amount: amount);
    if (!context.mounted) return;
    if (expenseId == null) {
      showNotice('Already recorded for this date');
      return;
    }
    final recorded = AppFormatters.formatCurrency(amount ?? template.amount);
    showNotice(
      '${_title(template)} recorded · $recorded',
      actionLabel: 'Undo',
      onAction: () => ref
          .read(recurringExpenseActionsProvider)
          .undoGenerated(before, expenseId),
    );
  }

  Future<void> _recordDifferent(BuildContext context, WidgetRef ref) async {
    final amount = await showResponsiveSheet<double>(
      context,
      maxWidth: 420,
      mobileChild: _AmountSheet(template: template, last: _lastAmount(ref)),
      desktopChild: _AmountSheet(template: template, last: _lastAmount(ref)),
    );
    if (amount == null || !context.mounted) return;
    await _record(context, ref, amount: amount);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final style = CategoryStyles.of(template.category);
    final kind = ref.watch(categoryKindsProvider).of(template.category);
    final isInvestment = kind == CategoryKind.investment;

    final daysLate = DateTime.now().difference(template.nextDueDate).inDays;
    final late = daysLate >= 1;
    final last = _lastAmount(ref);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isInvestment ? Icons.trending_up_rounded : style.icon,
              size: 18,
              color: isInvestment ? calm.positive : style.color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(template),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (late)
                      '$daysLate ${daysLate == 1 ? 'day' : 'days'} late'
                    else
                      'Due today',
                    if (last != null)
                      'last time ${AppFormatters.formatCurrency(last)}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    color: late ? calm.warning : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // The amount is the control for "it was a different number this
          // month" — the chevron is what says so.
          InkWell(
            onTap: () => _recordDifferent(context, ref),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppFormatters.formatCurrency(template.amount),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: cs.primary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 34,
            child: TextButton(
              onPressed: () => _record(context, ref),
              style: TextButton.styleFrom(
                foregroundColor: cs.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(56, 34),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: const Text('Paid'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Templates carry notes like "Flat 402" that name the bill better than the
/// category does.
String _title(RecurringExpenseTemplate template) {
  final notes = template.notes?.trim();
  return notes == null || notes.isEmpty ? template.category : notes;
}

/// Record this occurrence at a different figure. The template keeps its usual
/// amount — next month asks again from the same starting point.
class _AmountSheet extends StatefulWidget {
  final RecurringExpenseTemplate template;
  final double? last;

  const _AmountSheet({required this.template, this.last});

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  final _controller = TextEditingController();
  bool _showValidation = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.template.amount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _value {
    final value = parseAmountExpression(_controller.text.trim());
    return value != null && value > 0 ? value : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = _value;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title(widget.template),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.last == null
                ? 'Usually ${AppFormatters.formatCurrency(widget.template.amount)}'
                : 'Usually ${AppFormatters.formatCurrency(widget.template.amount)} · '
                      'last time ${AppFormatters.formatCurrency(widget.last!)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          AmountInput(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            showError: _showValidation && value == null,
          ),
          const SizedBox(height: 8),
          Text(
            'Recorded once, at this amount. The bill keeps its usual figure '
            'for next time.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          SaveExpenseButton(
            label: value == null
                ? 'Record'
                : 'Record ${AppFormatters.formatCurrency(value)}',
            isEnabled: value != null,
            onPressed: () {
              if (value == null) {
                setState(() => _showValidation = true);
                return;
              }
              Navigator.of(context).pop(value);
            },
          ),
        ],
      ),
    );
  }
}
