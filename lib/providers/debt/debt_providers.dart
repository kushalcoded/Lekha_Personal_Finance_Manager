import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/debt/person_balance.dart';
import '../../providers/budget/budget_providers.dart';
import '../../utils/formatters/formatters.dart';
import '../storage/storage_providers.dart';
import '../../screens/receivables/providers/receivables_providers.dart';

final personBalancesProvider = Provider.family<List<PersonBalance>, String>((
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

  final totals = <String, PersonBalance>{};

  for (final receivable in receivables) {
    final key = receivable.fromPerson.trim();
    final existing = totals[key];
    final nextReceivable = (existing?.receivableTotal ?? 0) + receivable.amount;
    totals[key] = PersonBalance(
      person: key,
      receivableTotal: nextReceivable,
      payableTotal: existing?.payableTotal ?? 0,
    );
  }

  for (final payable in payables) {
    final key = payable.toPerson.trim();
    final existing = totals[key];
    final nextPayable = (existing?.payableTotal ?? 0) + payable.remainingAmount;
    totals[key] = PersonBalance(
      person: key,
      receivableTotal: existing?.receivableTotal ?? 0,
      payableTotal: nextPayable,
    );
  }

  final results = totals.values.toList();
  results.sort((a, b) => b.netBalance.compareTo(a.netBalance));
  return results;
});

final netBalanceProvider = Provider.family<double, String>((ref, userId) {
  final receivablesTotal = ref.watch(totalReceivablesProvider(userId));
  final payablesTotal = ref.watch(totalPayablesProvider(userId));
  return receivablesTotal - payablesTotal;
});

final overduePayablesCountProvider = Provider.family<int, String>((
  ref,
  userId,
) {
  final payables = ref
      .watch(payablesProvider)
      .payables
      .where((item) => item.userId == userId)
      .toList();
  final today = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);
  return payables.where((payable) {
    if (payable.remainingAmount <= 0) return false;
    final due = DateTime(
      payable.dueDate.year,
      payable.dueDate.month,
      payable.dueDate.day,
    );
    return due.isBefore(todayOnly);
  }).length;
});

final overdueDebtCountProvider = Provider.family<int, String>((ref, userId) {
  final receivablesOverdue = ref
      .watch(receivablesStatsProvider(userId))
      .overdueCount;
  final payablesOverdue = ref.watch(overduePayablesCountProvider(userId));
  return receivablesOverdue + payablesOverdue;
});

final topDebtorsProvider = Provider.family<List<PersonBalance>, String>((
  ref,
  userId,
) {
  final balances = ref.watch(personBalancesProvider(userId));
  final filtered = balances.where((item) => item.receivableTotal > 0).toList();
  filtered.sort((a, b) => b.receivableTotal.compareTo(a.receivableTotal));
  return filtered.take(5).toList();
});

final topCreditorsProvider = Provider.family<List<PersonBalance>, String>((
  ref,
  userId,
) {
  final balances = ref.watch(personBalancesProvider(userId));
  final filtered = balances.where((item) => item.payableTotal > 0).toList();
  filtered.sort((a, b) => b.payableTotal.compareTo(a.payableTotal));
  return filtered.take(5).toList();
});

final debtInsightsProvider = Provider.family<List<SmartFinancialInsight>, String>((
  ref,
  userId,
) {
  final payablesTotal = ref.watch(totalPayablesProvider(userId));
  final receivablesStats = ref.watch(receivablesStatsProvider(userId));
  final overduePayables = ref.watch(overduePayablesCountProvider(userId));
  final netBalance = ref.watch(netBalanceProvider(userId));
  final balances = ref.watch(personBalancesProvider(userId));

  final insights = <SmartFinancialInsight>[];
  if (payablesTotal > 0) {
    final peopleOwed = balances.where((b) => b.payableTotal > 0).length;
    insights.add(
      SmartFinancialInsight(
        title: 'Outstanding payables',
        message:
            'You owe ${AppFormatters.formatCurrency(payablesTotal)} across '
            '$peopleOwed ${AppFormatters.plural(peopleOwed, 'person', 'people')}.',
        icon: Icons.payments_rounded,
        severity: InsightSeverity.warning,
      ),
    );
  }

  if (receivablesStats.overdueCount > 0) {
    insights.add(
      SmartFinancialInsight(
        title: 'Receivables overdue',
        message:
            '${receivablesStats.overdueCount} '
            '${AppFormatters.plural(receivablesStats.overdueCount, 'receivable', 'receivables')} '
            '${AppFormatters.plural(receivablesStats.overdueCount, 'is', 'are')} overdue.',
        icon: Icons.priority_high_rounded,
        severity: InsightSeverity.warning,
      ),
    );
  }

  if (overduePayables > 0) {
    insights.add(
      SmartFinancialInsight(
        title: 'Payables overdue',
        message:
            '$overduePayables '
            '${AppFormatters.plural(overduePayables, 'payable', 'payables')} '
            '${AppFormatters.plural(overduePayables, 'is', 'are')} past due.',
        icon: Icons.warning_amber_rounded,
        severity: InsightSeverity.danger,
      ),
    );
  }

  if (netBalance >= 0) {
    insights.add(
      const SmartFinancialInsight(
        title: 'Net positive balance',
        message: 'You are owed more than you owe this month.',
        icon: Icons.trending_up_rounded,
        severity: InsightSeverity.healthy,
      ),
    );
  } else {
    insights.add(
      const SmartFinancialInsight(
        title: 'Net negative balance',
        message: 'You owe more than what is owed to you.',
        icon: Icons.trending_down_rounded,
        severity: InsightSeverity.warning,
      ),
    );
  }

  return insights.take(3).toList();
});

final payableSettlementTotalProvider = Provider.family<double, String>((
  ref,
  userId,
) {
  final payables = ref.watch(payablesProvider).payables;
  return payables.fold(
    0.0,
    (sum, item) =>
        sum +
        (item.userId == userId ? (item.amount - item.remainingAmount) : 0),
  );
});
