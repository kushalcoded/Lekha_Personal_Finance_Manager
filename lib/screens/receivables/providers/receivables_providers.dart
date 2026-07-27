import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/receivable/receivable_model.dart';
import '../../../providers/storage/storage_providers.dart';

enum ReceivableStatus { pending, paid, overdue }

enum ReceivableStatusFilter { all, pending, paid, overdue }

class ReceivablesListState {
  final ReceivableStatusFilter filter;

  const ReceivablesListState({this.filter = ReceivableStatusFilter.all});

  ReceivablesListState copyWith({ReceivableStatusFilter? filter}) {
    return ReceivablesListState(filter: filter ?? this.filter);
  }
}

final receivablesListProvider =
    StateNotifierProvider<ReceivablesListNotifier, ReceivablesListState>(
      (ref) => ReceivablesListNotifier(),
    );

class ReceivablesListNotifier extends StateNotifier<ReceivablesListState> {
  ReceivablesListNotifier() : super(const ReceivablesListState());

  void setFilter(ReceivableStatusFilter filter) {
    state = state.copyWith(filter: filter);
  }
}

class ReceivablesStats {
  final double totalOwed;
  final double collectedAmount;
  final int overdueCount;
  final int activeReceivables;

  const ReceivablesStats({
    required this.totalOwed,
    required this.collectedAmount,
    required this.overdueCount,
    required this.activeReceivables,
  });
}

ReceivableStatus receivableStatus(Receivable receivable) {
  if (receivable.isPaid) {
    return ReceivableStatus.paid;
  }

  final today = DateTime.now();
  final dueDate = DateTime(
    receivable.dueDate.year,
    receivable.dueDate.month,
    receivable.dueDate.day,
  );
  final todayOnly = DateTime(today.year, today.month, today.day);

  if (dueDate.isBefore(todayOnly)) {
    return ReceivableStatus.overdue;
  }
  return ReceivableStatus.pending;
}

final filteredReceivablesProvider = Provider.family<List<Receivable>, String>((
  ref,
  userId,
) {
  final filter = ref.watch(receivablesListProvider).filter;
  final receivables =
      ref
          .watch(receivablesProvider)
          .receivables
          .where((receivable) => receivable.userId == userId)
          .toList()
        ..sort((a, b) {
          final aStatus = receivableStatus(a);
          final bStatus = receivableStatus(b);
          final statusCompare = _statusSortWeight(
            aStatus,
          ).compareTo(_statusSortWeight(bStatus));
          if (statusCompare != 0) {
            return statusCompare;
          }
          return a.dueDate.compareTo(b.dueDate);
        });

  if (filter == ReceivableStatusFilter.all) {
    return receivables;
  }

  return receivables.where((receivable) {
    final status = receivableStatus(receivable);
    switch (filter) {
      case ReceivableStatusFilter.pending:
        return status == ReceivableStatus.pending;
      case ReceivableStatusFilter.paid:
        return status == ReceivableStatus.paid;
      case ReceivableStatusFilter.overdue:
        return status == ReceivableStatus.overdue;
      case ReceivableStatusFilter.all:
        return true;
    }
  }).toList();
});

final receivablesStatsProvider = Provider.family<ReceivablesStats, String>((
  ref,
  userId,
) {
  final receivables = ref
      .watch(receivablesProvider)
      .receivables
      .where((receivable) => receivable.userId == userId)
      .toList();

  final totalOwed = receivables
      .where((receivable) => !receivable.isPaid)
      .fold(0.0, (sum, receivable) => sum + receivable.amount);
  final collectedAmount = receivables
      .where((receivable) => receivable.isPaid)
      .fold(0.0, (sum, receivable) => sum + receivable.amount);
  final overdueCount = receivables
      .where(
        (receivable) =>
            receivableStatus(receivable) == ReceivableStatus.overdue,
      )
      .length;
  final activeReceivables = receivables
      .where(
        (receivable) => receivableStatus(receivable) != ReceivableStatus.paid,
      )
      .length;

  return ReceivablesStats(
    totalOwed: totalOwed,
    collectedAmount: collectedAmount,
    overdueCount: overdueCount,
    activeReceivables: activeReceivables,
  );
});

int _statusSortWeight(ReceivableStatus status) {
  switch (status) {
    case ReceivableStatus.overdue:
      return 0;
    case ReceivableStatus.pending:
      return 1;
    case ReceivableStatus.paid:
      return 2;
  }
}
