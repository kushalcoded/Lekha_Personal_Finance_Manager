class DebtSummary {
  final double totalReceivables;
  final double totalPayables;
  final double netBalance;
  final int overdueReceivables;
  final int overduePayables;
  final double settledAmount;
  final int activeDebtors;
  final int activeCreditors;

  const DebtSummary({
    required this.totalReceivables,
    required this.totalPayables,
    required this.netBalance,
    required this.overdueReceivables,
    required this.overduePayables,
    required this.settledAmount,
    required this.activeDebtors,
    required this.activeCreditors,
  });
}

class DebtOverdueStats {
  final double overdueReceivablesTotal;
  final double overduePayablesTotal;
  final int overdueReceivablesCount;
  final int overduePayablesCount;

  const DebtOverdueStats({
    required this.overdueReceivablesTotal,
    required this.overduePayablesTotal,
    required this.overdueReceivablesCount,
    required this.overduePayablesCount,
  });
}
