import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/history/cycle_history_snapshot.dart';
import '../../../services/errors/error_reporter.dart';
import '../../../services/storage/hive_service.dart';
import '../../../services/supabase/supabase_service.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../../providers/auth/auth_provider.dart';

class SettingsState {
  final bool isLoading;
  final String? error;

  /// Name shown in the dashboard greeting; asked once after sign-in.
  final String displayName;
  final String currency;
  final bool analyticsInsightsEnabled;
  final String defaultExportFormat;
  final bool exportIncludeAnalyticsSummary;
  final bool remindersEnabled;
  final bool budgetWarningReminderEnabled;
  final bool overdueReceivableReminderEnabled;
  final bool recurringDueReminderEnabled;
  final bool monthlyBudgetReminderEnabled;
  final bool recurringQuickGenerateEnabled;
  final bool smsAutoDetectEnabled;

  /// Android only: post a notification with Add / Ignore the moment a bank SMS
  /// lands. Off by default — switching it on is what asks for the Android 13
  /// notification permission, which shouldn't ambush anyone at launch.
  final bool smsNotifyEnabled;

  /// Send a crash report when the app throws. No money data, no message text —
  /// the error, where it came from, and the app version. On by default because
  /// a bug nobody can reproduce is a bug nobody can fix.
  final bool errorReportsEnabled;
  final DateTime? salaryCycleStartDate;

  /// Day of the month salary usually lands (1–31), or null if not set. Only
  /// ever used to decide WHEN TO ASK about starting a new cycle — credit
  /// dates drift early and late, so the app never rolls a cycle on its own.
  final int? salaryDay;

  /// The expected roll date the user last dismissed, so the prompt asks once
  /// per cycle rather than every launch.
  final DateTime? cyclePromptDismissedFor;
  final double currentCycleBudget;
  final double currentCycleSalary;
  final List<CycleHistorySnapshot> cycleHistory;

  const SettingsState({
    this.isLoading = true,
    this.error,
    this.displayName = '',
    this.currency = 'INR',
    this.analyticsInsightsEnabled = true,
    this.defaultExportFormat = 'csv',
    this.exportIncludeAnalyticsSummary = true,
    this.remindersEnabled = true,
    this.budgetWarningReminderEnabled = true,
    this.overdueReceivableReminderEnabled = true,
    this.recurringDueReminderEnabled = true,
    this.monthlyBudgetReminderEnabled = true,
    this.recurringQuickGenerateEnabled = true,
    this.smsAutoDetectEnabled = true,
    this.smsNotifyEnabled = false,
    this.errorReportsEnabled = true,
    this.salaryCycleStartDate,
    this.salaryDay,
    this.cyclePromptDismissedFor,
    this.currentCycleBudget = 0.0,
    this.currentCycleSalary = 0.0,
    this.cycleHistory = const [],
  });

  DateTime get currentCycleStartDate {
    final date = salaryCycleStartDate;
    if (date != null) {
      return DateTime(date.year, date.month, date.day);
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  /// The first salary day strictly after the current cycle began — i.e. when
  /// this cycle is due to be replaced. Null when no salary day is set.
  DateTime? get expectedCycleRollDate => salaryDay == null
      ? null
      : nextSalaryDayAfter(currentCycleStartDate, salaryDay!);

  /// True once that date has arrived and the user hasn't dismissed it. The
  /// prompt is a question, never an action: salary lands early some months
  /// and late others, so the user confirms the real date.
  bool cycleRollDue([DateTime? now]) {
    final due = expectedCycleRollDate;
    if (due == null) return false;
    final today = now ?? DateTime.now();
    if (DateTime(today.year, today.month, today.day).isBefore(due)) {
      return false;
    }
    final dismissed = cyclePromptDismissedFor;
    return dismissed == null || !_sameDay(dismissed, due);
  }

  SettingsState copyWith({
    bool? isLoading,
    String? error,
    String? displayName,
    String? currency,
    bool? analyticsInsightsEnabled,
    String? defaultExportFormat,
    bool? exportIncludeAnalyticsSummary,
    bool? remindersEnabled,
    bool? budgetWarningReminderEnabled,
    bool? overdueReceivableReminderEnabled,
    bool? recurringDueReminderEnabled,
    bool? monthlyBudgetReminderEnabled,
    bool? recurringQuickGenerateEnabled,
    bool? smsAutoDetectEnabled,
    bool? smsNotifyEnabled,
    bool? errorReportsEnabled,
    DateTime? salaryCycleStartDate,
    int? salaryDay,
    DateTime? cyclePromptDismissedFor,
    double? currentCycleBudget,
    double? currentCycleSalary,
    List<CycleHistorySnapshot>? cycleHistory,
  }) {
    return SettingsState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      displayName: displayName ?? this.displayName,
      currency: currency ?? this.currency,
      analyticsInsightsEnabled:
          analyticsInsightsEnabled ?? this.analyticsInsightsEnabled,
      defaultExportFormat: defaultExportFormat ?? this.defaultExportFormat,
      exportIncludeAnalyticsSummary:
          exportIncludeAnalyticsSummary ?? this.exportIncludeAnalyticsSummary,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      budgetWarningReminderEnabled:
          budgetWarningReminderEnabled ?? this.budgetWarningReminderEnabled,
      overdueReceivableReminderEnabled:
          overdueReceivableReminderEnabled ??
          this.overdueReceivableReminderEnabled,
      recurringDueReminderEnabled:
          recurringDueReminderEnabled ?? this.recurringDueReminderEnabled,
      monthlyBudgetReminderEnabled:
          monthlyBudgetReminderEnabled ?? this.monthlyBudgetReminderEnabled,
      recurringQuickGenerateEnabled:
          recurringQuickGenerateEnabled ?? this.recurringQuickGenerateEnabled,
      smsAutoDetectEnabled: smsAutoDetectEnabled ?? this.smsAutoDetectEnabled,
      smsNotifyEnabled: smsNotifyEnabled ?? this.smsNotifyEnabled,
      errorReportsEnabled: errorReportsEnabled ?? this.errorReportsEnabled,
      salaryCycleStartDate: salaryCycleStartDate ?? this.salaryCycleStartDate,
      salaryDay: salaryDay ?? this.salaryDay,
      cyclePromptDismissedFor:
          cyclePromptDismissedFor ?? this.cyclePromptDismissedFor,
      currentCycleBudget: currentCycleBudget ?? this.currentCycleBudget,
      currentCycleSalary: currentCycleSalary ?? this.currentCycleSalary,
      cycleHistory: cycleHistory ?? this.cycleHistory,
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The next occurrence of [day] strictly after [from], clamped to the target
/// month's length so a salary day of 31 still lands in February.
DateTime nextSalaryDayAfter(DateTime from, int day) {
  DateTime inMonth(int year, int month) {
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, lastDayOfMonth));
  }

  final start = DateTime(from.year, from.month, from.day);
  final thisMonth = inMonth(start.year, start.month);
  if (thisMonth.isAfter(start)) return thisMonth;
  return inMonth(start.year, start.month + 1);
}

/// The most recent occurrence of [day] on or before [from], clamped to the
/// month's length so a salary day of 31 still lands in February.
///
/// Setup uses this: someone paid on the 7th should not have a cycle that
/// silently started on the 1st, which is the default when nobody has said.
DateTime lastSalaryDayOnOrBefore(DateTime from, int day) {
  DateTime inMonth(int year, int month) {
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, lastDayOfMonth));
  }

  final start = DateTime(from.year, from.month, from.day);
  final thisMonth = inMonth(start.year, start.month);
  if (!thisMonth.isAfter(start)) return thisMonth;
  return inMonth(start.year, start.month - 1);
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final HiveService _hiveService;
  final String _userId;

  SettingsNotifier(this._hiveService, this._userId)
    : super(const SettingsState()) {
    loadSettings();
  }

  Future<void> loadSettings() async {
    state = state.copyWith(isLoading: true);
    try {
      final raw = _hiveService.getSettings(_userId);
      final now = DateTime.now();
      final rawCycleStart = raw['salaryCycleStartDate'] as String?;
      final parsedCycleStart = rawCycleStart == null
          ? null
          : DateTime.tryParse(rawCycleStart);
      final rawBudget =
          (raw['currentCycleBudget'] as num?)?.toDouble() ??
          _hiveService.getMonthlyBudget(_userId, now);
      final rawSalary = (raw['currentCycleSalary'] as num?)?.toDouble() ?? 0.0;
      state = SettingsState(
        isLoading: false,
        displayName: raw['displayName'] as String? ?? '',
        currency: raw['currency'] as String? ?? 'INR',
        analyticsInsightsEnabled:
            raw['analyticsInsightsEnabled'] as bool? ?? true,
        defaultExportFormat: raw['defaultExportFormat'] as String? ?? 'csv',
        exportIncludeAnalyticsSummary:
            raw['exportIncludeAnalyticsSummary'] as bool? ?? true,
        remindersEnabled: raw['remindersEnabled'] as bool? ?? true,
        budgetWarningReminderEnabled:
            raw['budgetWarningReminderEnabled'] as bool? ?? true,
        overdueReceivableReminderEnabled:
            raw['overdueReceivableReminderEnabled'] as bool? ?? true,
        recurringDueReminderEnabled:
            raw['recurringDueReminderEnabled'] as bool? ?? true,
        monthlyBudgetReminderEnabled:
            raw['monthlyBudgetReminderEnabled'] as bool? ?? true,
        recurringQuickGenerateEnabled:
            raw['recurringQuickGenerateEnabled'] as bool? ?? true,
        smsAutoDetectEnabled: raw['smsAutoDetectEnabled'] as bool? ?? true,
        smsNotifyEnabled: raw['smsNotifyEnabled'] as bool? ?? false,
        errorReportsEnabled: raw['errorReportsEnabled'] as bool? ?? true,
        salaryCycleStartDate:
            parsedCycleStart ?? DateTime(now.year, now.month, 1),
        salaryDay: (raw['salaryDay'] as num?)?.toInt(),
        cyclePromptDismissedFor: DateTime.tryParse(
          raw['cyclePromptDismissedFor'] as String? ?? '',
        ),
        currentCycleBudget: rawBudget,
        currentCycleSalary: rawSalary,
        cycleHistory: _hiveService.getCycleHistory(_userId),
      );
      // The reporter is installed before the first frame, long before this
      // runs, so it starts enabled and learns the stored answer here.
      ErrorReporter.enabled = state.errorReportsEnabled;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> _persist(SettingsState next) async {
    state = next.copyWith(error: null);
    // Overlay onto whatever is already stored instead of replacing it. Other
    // features keep their own keys in this same map — custom categories,
    // payment methods, export history — and none of them are represented on
    // SettingsState. Writing a fresh literal deleted them: flipping any toggle
    // used to wipe every custom category back to the defaults.
    final stored = _hiveService.getSettings(_userId);
    await _hiveService.saveSettings(_userId, {
      ...stored,
      'displayName': next.displayName,
      'currency': next.currency,
      'analyticsInsightsEnabled': next.analyticsInsightsEnabled,
      'defaultExportFormat': next.defaultExportFormat,
      'exportIncludeAnalyticsSummary': next.exportIncludeAnalyticsSummary,
      'remindersEnabled': next.remindersEnabled,
      'budgetWarningReminderEnabled': next.budgetWarningReminderEnabled,
      'overdueReceivableReminderEnabled': next.overdueReceivableReminderEnabled,
      'recurringDueReminderEnabled': next.recurringDueReminderEnabled,
      'monthlyBudgetReminderEnabled': next.monthlyBudgetReminderEnabled,
      'recurringQuickGenerateEnabled': next.recurringQuickGenerateEnabled,
      'smsAutoDetectEnabled': next.smsAutoDetectEnabled,
      'smsNotifyEnabled': next.smsNotifyEnabled,
      'errorReportsEnabled': next.errorReportsEnabled,
      'salaryCycleStartDate': next.currentCycleStartDate.toIso8601String(),
      'salaryDay': next.salaryDay,
      'cyclePromptDismissedFor': next.cyclePromptDismissedFor
          ?.toIso8601String(),
      'currentCycleBudget': next.currentCycleBudget,
      'currentCycleSalary': next.currentCycleSalary,
      'cycleHistory': next.cycleHistory.map((entry) => entry.toJson()).toList(),
    });
  }

  Future<void> setCurrency(String value) async {
    await _persist(state.copyWith(currency: value));
  }

  Future<void> setDisplayName(String value) async {
    await _persist(state.copyWith(displayName: value.trim()));
  }

  Future<void> setAnalyticsInsightsEnabled(bool value) async {
    await _persist(state.copyWith(analyticsInsightsEnabled: value));
  }

  Future<void> setSmsAutoDetectEnabled(bool value) async {
    await _persist(state.copyWith(smsAutoDetectEnabled: value));
  }

  Future<void> setSmsNotifyEnabled(bool value) async {
    await _persist(state.copyWith(smsNotifyEnabled: value));
  }

  Future<void> setErrorReportsEnabled(bool value) async {
    ErrorReporter.enabled = value;
    await _persist(state.copyWith(errorReportsEnabled: value));
  }

  Future<void> setDefaultExportFormat(String value) async {
    await _persist(state.copyWith(defaultExportFormat: value));
  }

  Future<void> setExportIncludeAnalyticsSummary(bool value) async {
    await _persist(state.copyWith(exportIncludeAnalyticsSummary: value));
  }

  Future<void> setRemindersEnabled(bool value) async {
    await _persist(state.copyWith(remindersEnabled: value));
  }

  Future<void> setBudgetWarningReminderEnabled(bool value) async {
    await _persist(state.copyWith(budgetWarningReminderEnabled: value));
  }

  Future<void> setOverdueReceivableReminderEnabled(bool value) async {
    await _persist(state.copyWith(overdueReceivableReminderEnabled: value));
  }

  Future<void> setRecurringDueReminderEnabled(bool value) async {
    await _persist(state.copyWith(recurringDueReminderEnabled: value));
  }

  Future<void> setMonthlyBudgetReminderEnabled(bool value) async {
    await _persist(state.copyWith(monthlyBudgetReminderEnabled: value));
  }

  Future<void> setRecurringQuickGenerateEnabled(bool value) async {
    await _persist(state.copyWith(recurringQuickGenerateEnabled: value));
  }

  Future<void> setCycleBudget(double value) async {
    final next = state.copyWith(currentCycleBudget: value);
    await _persist(next);
    await _hiveService.setMonthlyBudget(_userId, DateTime.now(), value);
  }

  Future<void> resetCycleBudget() async {
    final next = state.copyWith(currentCycleBudget: 0.0);
    await _persist(next);
    await _hiveService.resetMonthlyBudget(_userId, DateTime.now());
  }

  Future<void> setCycleSalary(double value) async {
    await _persist(state.copyWith(currentCycleSalary: value));
  }

  Future<void> resetCycleSalary() async {
    await _persist(state.copyWith(currentCycleSalary: 0.0));
  }

  /// The day salary usually arrives. Pass null to stop being asked.
  Future<void> setSalaryDay(int? day) async {
    await _persist(
      SettingsState(
        isLoading: false,
        displayName: state.displayName,
        currency: state.currency,
        analyticsInsightsEnabled: state.analyticsInsightsEnabled,
        defaultExportFormat: state.defaultExportFormat,
        exportIncludeAnalyticsSummary: state.exportIncludeAnalyticsSummary,
        remindersEnabled: state.remindersEnabled,
        budgetWarningReminderEnabled: state.budgetWarningReminderEnabled,
        overdueReceivableReminderEnabled:
            state.overdueReceivableReminderEnabled,
        recurringDueReminderEnabled: state.recurringDueReminderEnabled,
        monthlyBudgetReminderEnabled: state.monthlyBudgetReminderEnabled,
        recurringQuickGenerateEnabled: state.recurringQuickGenerateEnabled,
        smsAutoDetectEnabled: state.smsAutoDetectEnabled,
        smsNotifyEnabled: state.smsNotifyEnabled,
        errorReportsEnabled: state.errorReportsEnabled,
        salaryCycleStartDate: state.salaryCycleStartDate,
        // copyWith can't clear a null-able field, and this one must be
        // clearable to turn the reminder off.
        salaryDay: day,
        cyclePromptDismissedFor: state.cyclePromptDismissedFor,
        currentCycleBudget: state.currentCycleBudget,
        currentCycleSalary: state.currentCycleSalary,
        cycleHistory: state.cycleHistory,
      ),
    );
  }

  /// Stop asking about this particular roll — the next one still prompts.
  Future<void> dismissCyclePrompt() async {
    final due = state.expectedCycleRollDate;
    if (due == null) return;
    await _persist(state.copyWith(cyclePromptDismissedFor: due));
  }

  Future<void> resetSalaryCycle({DateTime? startDate}) async {
    final date = startDate ?? DateTime.now();
    final newCycleStart = DateTime(date.year, date.month, date.day);
    final previousCycleStart = state.currentCycleStartDate;
    final snapshot = _hiveService.createCycleHistorySnapshot(
      userId: _userId,
      cycleStartDate: previousCycleStart,
      newCycleStartDate: newCycleStart,
      cycleBudget: state.currentCycleBudget,
      cycleSalary: state.currentCycleSalary,
    );
    final shouldArchive =
        previousCycleStart.isBefore(newCycleStart) &&
        (state.currentCycleBudget > 0 ||
            state.currentCycleSalary > 0 ||
            snapshot.expenses.isNotEmpty);

    var nextHistory = state.cycleHistory;
    if (shouldArchive) {
      await _hiveService.addCycleHistorySnapshot(_userId, snapshot);
      nextHistory = _hiveService.getCycleHistory(_userId);
    }

    await _persist(
      state.copyWith(
        salaryCycleStartDate: newCycleStart,
        cycleHistory: nextHistory,
      ),
    );
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    final hiveService = ref.watch(hiveServiceProvider);
    final userId = ref.watch(currentUserIdProvider) ?? '';
    return SettingsNotifier(hiveService, userId);
  },
);

final currenciesProvider = Provider<List<String>>((ref) {
  return ['INR', 'USD', 'EUR', 'GBP', 'AUD', 'CAD'];
});

final exportFormatsProvider = Provider<List<String>>((ref) {
  return ['csv', 'excel', 'pdf'];
});

/// Debug provider for Supabase connection testing
class SupabaseDebugState {
  final bool isLoading;

  const SupabaseDebugState({this.isLoading = false});
}

class SupabaseDebugNotifier extends StateNotifier<SupabaseDebugState> {
  SupabaseDebugNotifier() : super(const SupabaseDebugState());

  Future<String> testConnection() async {
    state = const SupabaseDebugState(isLoading: true);
    try {
      final message = await SupabaseService.testConnection();
      state = const SupabaseDebugState();
      return message;
    } catch (e) {
      state = const SupabaseDebugState();
      throw e.toString();
    }
  }
}

final supabaseDebugProvider =
    StateNotifierProvider<SupabaseDebugNotifier, SupabaseDebugState>(
      (ref) => SupabaseDebugNotifier(),
    );
