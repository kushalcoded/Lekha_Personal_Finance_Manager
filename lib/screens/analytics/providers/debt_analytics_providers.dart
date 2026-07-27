import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/debt/person_balance.dart';
import '../../../providers/debt/debt_providers.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../receivables/providers/receivables_providers.dart';
import '../models/analytics_models.dart';
import '../models/debt_models.dart';

final debtSummaryProvider = Provider.family<DebtSummary, String>((ref, userId) {
  final receivablesStats = ref.watch(receivablesStatsProvider(userId));
  final receivablesTotal = ref.watch(totalReceivablesProvider(userId));
  final payablesTotal = ref.watch(totalPayablesProvider(userId));
  final netBalance = ref.watch(netBalanceProvider(userId));
  final overduePayables = ref.watch(overduePayablesCountProvider(userId));
  final settlements = ref.watch(payableSettlementTotalProvider(userId));
  final balances = ref.watch(personBalancesProvider(userId));

  final activeDebtors = balances.where((b) => b.receivableTotal > 0).length;
  final activeCreditors = balances.where((b) => b.payableTotal > 0).length;

  return DebtSummary(
    totalReceivables: receivablesTotal,
    totalPayables: payablesTotal,
    netBalance: netBalance,
    overdueReceivables: receivablesStats.overdueCount,
    overduePayables: overduePayables,
    settledAmount: settlements,
    activeDebtors: activeDebtors,
    activeCreditors: activeCreditors,
  );
});

final debtOverdueStatsProvider = Provider.family<DebtOverdueStats, String>((
  ref,
  userId,
) {
  final receivables = ref
      .watch(receivablesProvider)
      .receivables
      .where((item) => item.userId == userId && !item.isPaid)
      .toList();
  final payables = ref
      .watch(payablesProvider)
      .payables
      .where((item) => item.userId == userId && item.remainingAmount > 0)
      .toList();

  final today = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);

  double receivableTotal = 0.0;
  int receivableCount = 0;
  for (final receivable in receivables) {
    final due = DateTime(
      receivable.dueDate.year,
      receivable.dueDate.month,
      receivable.dueDate.day,
    );
    if (due.isBefore(todayOnly)) {
      receivableTotal += receivable.amount;
      receivableCount += 1;
    }
  }

  double payableTotal = 0.0;
  int payableCount = 0;
  for (final payable in payables) {
    final due = DateTime(
      payable.dueDate.year,
      payable.dueDate.month,
      payable.dueDate.day,
    );
    if (due.isBefore(todayOnly)) {
      payableTotal += payable.remainingAmount;
      payableCount += 1;
    }
  }

  return DebtOverdueStats(
    overdueReceivablesTotal: receivableTotal,
    overduePayablesTotal: payableTotal,
    overdueReceivablesCount: receivableCount,
    overduePayablesCount: payableCount,
  );
});

final debtTrendProvider = Provider.family<List<TrendPoint>, String>((
  ref,
  userId,
) {
  final receivables = ref.watch(receivablesProvider).receivables;
  final payables = ref.watch(payablesProvider).payables;
  final now = DateTime.now();
  final anchor = DateTime(now.year, now.month, 1);
  final months = List.generate(6, (index) {
    return _shiftMonth(anchor, index - 5);
  });

  return months.map((monthStart) {
    final monthEnd = _shiftMonth(monthStart, 1);
    final receivableTotal = receivables
        .where(
          (item) =>
              item.userId == userId &&
              !item.createdAt.isBefore(monthStart) &&
              item.createdAt.isBefore(monthEnd),
        )
        .fold(0.0, (sum, item) => sum + item.amount);
    final payableTotal = payables
        .where(
          (item) =>
              item.userId == userId &&
              !item.createdAt.isBefore(monthStart) &&
              item.createdAt.isBefore(monthEnd),
        )
        .fold(0.0, (sum, item) => sum + item.amount);

    return TrendPoint(date: monthStart, total: receivableTotal - payableTotal);
  }).toList();
});

final monthlySettlementTotalsProvider =
    Provider.family<List<MonthlyTotal>, String>((ref, userId) {
      final payables = ref
          .watch(payablesProvider)
          .payables
          .where((item) => item.userId == userId)
          .toList();
      final now = DateTime.now();
      final anchor = DateTime(now.year, now.month, 1);
      final months = List.generate(6, (index) {
        return _shiftMonth(anchor, index - 5);
      });

      return months.map((monthStart) {
        final monthEnd = _shiftMonth(monthStart, 1);
        double total = 0.0;
        for (final payable in payables) {
          for (final settlement in payable.settlements) {
            if (!settlement.settledAt.isBefore(monthStart) &&
                settlement.settledAt.isBefore(monthEnd)) {
              total += settlement.amount;
            }
          }
        }
        return MonthlyTotal(month: monthStart, total: total);
      }).toList();
    });

final topDebtorsBalanceProvider = Provider.family<List<PersonBalance>, String>((
  ref,
  userId,
) {
  return ref.watch(topDebtorsProvider(userId));
});

final topCreditorsBalanceProvider =
    Provider.family<List<PersonBalance>, String>((ref, userId) {
      return ref.watch(topCreditorsProvider(userId));
    });

DateTime _shiftMonth(DateTime date, int months) {
  return DateTime(date.year, date.month + months, 1);
}
