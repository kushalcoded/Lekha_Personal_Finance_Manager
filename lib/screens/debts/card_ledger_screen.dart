import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/category_styles.dart';
import '../../models/category/expense_category.dart';
import '../../models/expense/expense_model.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/categories/category_providers.dart';
import '../../providers/clock_provider.dart';
import '../../providers/payment/card_providers.dart';
import '../../providers/storage/storage_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters/formatters.dart';
import '../../widgets/common/form_bits.dart';
import '../../widgets/common/glass.dart';
import '../expenses/utils/expense_helpers.dart';
import 'widgets/pay_bill_sheet.dart';

/// One card: what is owed, what the closed statement asked for, and the
/// purchases behind it.
///
/// Shaped like the person ledger on purpose — the balance at the top, one
/// action, then the items — because a card bill is the same kind of thing as
/// money owed to a person, and the screen should feel familiar the first time
/// it opens.
class CardLedgerScreen extends ConsumerWidget {
  final CardConfig card;

  const CardLedgerScreen({super.key, required this.card});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final kinds = ref.watch(categoryKindsProvider);
    final mine = ref
        .watch(expensesProvider)
        .expenses
        .where((e) => e.userId == userId)
        .toList();

    final outstanding = cardOutstanding(mine, card.method, kinds);
    final now = ref.watch(nowProvider)();
    final period = card.hasCycle
        ? cardStatementPeriod(
            statementDay: card.statementDay!,
            dueDay: card.dueDay!,
            now: now,
          )
        : null;
    final statement = period == null
        ? 0.0
        : statementTotal(
            mine,
            card.method,
            kinds,
            periodStart: period.periodStart,
            statementDate: period.statementDate,
          );

    // Everything on this card, newest first — purchases and the payments
    // against them in one thread, which is how a statement reads.
    final rows =
        mine
            .where(
              (e) =>
                  expensePaymentMethod(e) == card.method &&
                  (kinds.spends(e.category) ||
                      kinds.of(e.category) == CategoryKind.transfer),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(card.method),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          GlassCard(
            color: outstanding > 0.005
                ? cs.error.withValues(alpha: 0.07)
                : null,
            border: outstanding > 0.005
                ? Border.all(color: cs.error.withValues(alpha: 0.28))
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FieldLabel(
                  outstanding < -0.005 ? 'In credit' : 'Outstanding',
                  color: outstanding > 0.005 ? cs.error : null,
                ),
                const SizedBox(height: 6),
                Text(
                  AppFormatters.formatCurrency(outstanding.abs()),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: outstanding > 0.005
                        ? cs.error
                        : outstanding < -0.005
                        ? calm.positive
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _summaryLine(period, statement, outstanding),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => showPayBillSheet(
                context,
                method: card.method,
                outstanding: outstanding,
                statementDue: statement,
              ),
              child: const Text('Pay bill'),
            ),
          ),
          const SizedBox(height: 20),
          FieldLabel(period == null ? 'On this card' : 'This statement'),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text(
              'Nothing on this card yet. Expenses paid with '
              '"${card.method}" show up here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            )
          else
            ...rows.map(
              (e) => _CardRow(
                expense: e,
                isPayment: kinds.of(e.category) == CategoryKind.transfer,
              ),
            ),
        ],
      ),
    );
  }

  String _summaryLine(
    ({DateTime periodStart, DateTime statementDate, DateTime dueDate})? period,
    double statement,
    double outstanding,
  ) {
    if (period == null) {
      return 'Set a statement day in Settings → Payment methods to see what '
          'this month\'s bill comes to.';
    }
    final since = outstanding - statement;
    return [
      'Statement ${AppFormatters.formatCurrency(statement)}, closed '
          '${AppFormatters.formatDate(period.statementDate)}',
      'due ${AppFormatters.formatDate(period.dueDate)}',
      if (since > 0.005) '${AppFormatters.formatCurrency(since)} spent since',
    ].join(' · ');
  }
}

class _CardRow extends StatelessWidget {
  final Expense expense;
  final bool isPayment;

  const _CardRow({required this.expense, required this.isPayment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final style = CategoryStyles.of(expense.category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 12,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (isPayment ? calm.positive : style.color).withValues(
                  alpha: 0.16,
                ),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                isPayment ? Icons.south_west_rounded : style.icon,
                size: 17,
                color: isPayment ? calm.positive : style.color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.description ?? expense.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppFormatters.formatDate(expense.date),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              isPayment
                  ? '− ${AppFormatters.formatCurrency(expense.amount)}'
                  : AppFormatters.formatCurrency(expense.amount),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isPayment ? calm.positive : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
