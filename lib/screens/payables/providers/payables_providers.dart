import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/payable/payable_model.dart';
import '../../../providers/storage/storage_providers.dart';

enum PayableStatusFilter { all, pending, partial, paid, overdue }

enum PayableDisplayStatus { pending, partial, paid, overdue }

class PayablesListState {
  final PayableStatusFilter filter;

  const PayablesListState({this.filter = PayableStatusFilter.all});

  PayablesListState copyWith({PayableStatusFilter? filter}) {
    return PayablesListState(filter: filter ?? this.filter);
  }
}

final payablesListProvider =
    StateNotifierProvider<PayablesListNotifier, PayablesListState>(
      (ref) => PayablesListNotifier(),
    );

class PayablesListNotifier extends StateNotifier<PayablesListState> {
  PayablesListNotifier() : super(const PayablesListState());

  void setFilter(PayableStatusFilter filter) {
    state = state.copyWith(filter: filter);
  }
}

class PayablesStats {
  final double totalOwed;
  final double totalSettled;
  final int overdueCount;
  final int activeCount;

  const PayablesStats({
    required this.totalOwed,
    required this.totalSettled,
    required this.overdueCount,
    required this.activeCount,
  });
}

PayableDisplayStatus payableDisplayStatus(Payable payable) {
  if (payable.remainingAmount <= 0 || payable.status == PayableStatus.paid) {
    return PayableDisplayStatus.paid;
  }
  if (_isOverdue(payable)) {
    return PayableDisplayStatus.overdue;
  }
  if (payable.status == PayableStatus.partial) {
    return PayableDisplayStatus.partial;
  }
  return PayableDisplayStatus.pending;
}

final filteredPayablesProvider = Provider.family<List<Payable>, String>((
  ref,
  userId,
) {
  final filter = ref.watch(payablesListProvider).filter;
  final payables =
      ref
          .watch(payablesProvider)
          .payables
          .where((payable) => payable.userId == userId)
          .toList()
        ..sort((a, b) {
          final aStatus = payableDisplayStatus(a);
          final bStatus = payableDisplayStatus(b);
          final statusCompare = _statusSortWeight(
            aStatus,
          ).compareTo(_statusSortWeight(bStatus));
          if (statusCompare != 0) {
            return statusCompare;
          }
          return a.dueDate.compareTo(b.dueDate);
        });

  if (filter == PayableStatusFilter.all) {
    return payables;
  }

  return payables.where((payable) {
    final status = payableDisplayStatus(payable);
    switch (filter) {
      case PayableStatusFilter.pending:
        return status == PayableDisplayStatus.pending;
      case PayableStatusFilter.partial:
        return status == PayableDisplayStatus.partial;
      case PayableStatusFilter.paid:
        return status == PayableDisplayStatus.paid;
      case PayableStatusFilter.overdue:
        return status == PayableDisplayStatus.overdue;
      case PayableStatusFilter.all:
        return true;
    }
  }).toList();
});

final payablesStatsProvider = Provider.family<PayablesStats, String>((
  ref,
  userId,
) {
  final payables = ref
      .watch(payablesProvider)
      .payables
      .where((payable) => payable.userId == userId)
      .toList();

  final totalOwed = payables.fold(
    0.0,
    (sum, payable) => sum + payable.remainingAmount,
  );
  final totalSettled = payables.fold(
    0.0,
    (sum, payable) => sum + (payable.amount - payable.remainingAmount),
  );
  final overdueCount = payables
      .where(
        (payable) =>
            payableDisplayStatus(payable) == PayableDisplayStatus.overdue,
      )
      .length;
  final activeCount = payables
      .where(
        (payable) => payableDisplayStatus(payable) != PayableDisplayStatus.paid,
      )
      .length;

  return PayablesStats(
    totalOwed: totalOwed,
    totalSettled: totalSettled,
    overdueCount: overdueCount,
    activeCount: activeCount,
  );
});

bool _isOverdue(Payable payable) {
  final today = DateTime.now();
  final due = DateTime(
    payable.dueDate.year,
    payable.dueDate.month,
    payable.dueDate.day,
  );
  final todayOnly = DateTime(today.year, today.month, today.day);
  return due.isBefore(todayOnly) && payable.remainingAmount > 0;
}

int _statusSortWeight(PayableDisplayStatus status) {
  switch (status) {
    case PayableDisplayStatus.overdue:
      return 0;
    case PayableDisplayStatus.pending:
      return 1;
    case PayableDisplayStatus.partial:
      return 2;
    case PayableDisplayStatus.paid:
      return 3;
  }
}
