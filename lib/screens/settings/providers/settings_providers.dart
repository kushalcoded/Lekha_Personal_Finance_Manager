import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/history/cycle_history_snapshot.dart';
import '../../../services/storage/hive_service.dart';
import '../../../services/supabase/supabase_service.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../../providers/auth/auth_provider.dart';

class SettingsState {
  final bool isLoading;
  final String? error;
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
  final DateTime? salaryCycleStartDate;
  final double currentCycleBudget;
  final double currentCycleSalary;
  final List<CycleHistorySnapshot> cycleHistory;

  const SettingsState({
    this.isLoading = true,
    this.error,
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
    this.salaryCycleStartDate,
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

  SettingsState copyWith({
    bool? isLoading,
    String? error,
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
    DateTime? salaryCycleStartDate,
    double? currentCycleBudget,
    double? currentCycleSalary,
    List<CycleHistorySnapshot>? cycleHistory,
  }) {
    return SettingsState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
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
      salaryCycleStartDate: salaryCycleStartDate ?? this.salaryCycleStartDate,
      currentCycleBudget: currentCycleBudget ?? this.currentCycleBudget,
      currentCycleSalary: currentCycleSalary ?? this.currentCycleSalary,
      cycleHistory: cycleHistory ?? this.cycleHistory,
    );
  }
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
        salaryCycleStartDate:
            parsedCycleStart ?? DateTime(now.year, now.month, 1),
        currentCycleBudget: rawBudget,
        currentCycleSalary: rawSalary,
        cycleHistory: _hiveService.getCycleHistory(_userId),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> _persist(SettingsState next) async {
    state = next.copyWith(error: null);
    await _hiveService.saveSettings(_userId, {
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
      'salaryCycleStartDate': next.currentCycleStartDate.toIso8601String(),
      'currentCycleBudget': next.currentCycleBudget,
      'currentCycleSalary': next.currentCycleSalary,
      'cycleHistory': next.cycleHistory.map((entry) => entry.toJson()).toList(),
    });
  }

  Future<void> setCurrency(String value) async {
    await _persist(state.copyWith(currency: value));
  }

  Future<void> setAnalyticsInsightsEnabled(bool value) async {
    await _persist(state.copyWith(analyticsInsightsEnabled: value));
  }

  Future<void> setSmsAutoDetectEnabled(bool value) async {
    await _persist(state.copyWith(smsAutoDetectEnabled: value));
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
