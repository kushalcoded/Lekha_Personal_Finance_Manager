import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../models/category/expense_category.dart';
import '../../models/expense/expense_hive_model.dart';
import '../../models/expense/expense_model.dart';
import '../../models/history/cycle_history_snapshot.dart';
import '../../models/payable/payable_model.dart';
import '../../models/pending/pending_transaction.dart';
import '../../models/recurring/recurring_expense_template.dart';
import '../../models/receivable/receivable_hive_model.dart';
import '../../models/receivable/receivable_model.dart';
import '../../models/sync/sync_models.dart';

/// Device-local UI state (AI chat history, last open tab). Never synced,
/// never backed up — each device keeps its own.
const kLocalPrefsBox = 'local_prefs';

class HiveService {
  static final HiveService _instance = HiveService._internal();

  late Box<ExpenseHive> _expensesBox;
  late Box<ReceivableHive> _receivablesBox;
  late Box<double> _monthlyBudgetsBox;
  late Box<Map> _recurringTemplatesBox;
  late Box<Map> _payablesBox;
  late Box<Map> _settingsBox;
  late Box<Map> _backupsBox;
  late Box<Map> _syncMetadataBox;
  late Box<Map> _syncStateBox;
  late Box<bool> _onboardingBox;
  late Box<Map> _pendingBox;
  late Box<bool> _smsSeenBox;
  bool _initialized = false;
  static const _syncDeviceIdKey = 'syncDeviceId';
  static const _localUserId = 'local_android_user';

  /// Fired after any user-data mutation (add/edit/delete, settings, budgets,
  /// pending SMS). The app wires this to a debounced cloud push so changes
  /// reach other devices without waiting for an app background.
  static void Function()? onDataChanged;
  bool _restoring = false;

  /// When the last local mutation happened. Sync compares this against its
  /// last-synced marker so a pull can never overwrite edits that haven't been
  /// pushed yet (e.g. an expense added seconds ago, still in the debounce).
  ///
  /// Persisted, not just in memory: it used to reset to null on every launch,
  /// so a cold start always looked "clean" and let a pull overwrite work that
  /// had never been pushed — the app forgot changes made just before it closed.
  DateTime? get lastLocalMutationAt {
    if (_memoryMutationAt != null) return _memoryMutationAt;
    if (!_initialized) return null;
    final raw = _syncStateBox.get(_mutationKey)?['at'];
    return raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
  }

  DateTime? _memoryMutationAt;
  static const _mutationKey = '__lastLocalMutationAt';

  /// Called once a push succeeds: everything local is now in the cloud, so a
  /// later pull is safe again. Without this the device would never pull.
  Future<void> clearLocalMutationMarker() async {
    _memoryMutationAt = null;
    if (!_initialized) return;
    await _syncStateBox.delete(_mutationKey);
  }

  void _notifyChanged() {
    // A restore IS the newest data — pushing it straight back up is noise.
    if (_restoring) return;
    final now = DateTime.now().toUtc();
    _memoryMutationAt = now;
    if (_initialized) {
      // Fire-and-forget: the in-memory value already answers this session, and
      // blocking every write on a disk round-trip isn't worth it.
      _syncStateBox.put(_mutationKey, {'at': now.toIso8601String()});
    }
    onDataChanged?.call();
  }

  factory HiveService() {
    return _instance;
  }

  HiveService._internal();

  bool get isInitialized => _initialized;

  static Future<void> initialize() async {
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ExpenseHiveAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ReceivableHiveAdapter());
    }

    _instance._expensesBox = await Hive.openBox<ExpenseHive>('expenses');
    _instance._receivablesBox = await Hive.openBox<ReceivableHive>(
      'receivables',
    );
    _instance._monthlyBudgetsBox = await Hive.openBox<double>(
      'monthly_budgets',
    );
    _instance._recurringTemplatesBox = await Hive.openBox<Map>(
      'recurring_templates',
    );
    _instance._payablesBox = await Hive.openBox<Map>('payables');
    _instance._settingsBox = await Hive.openBox<Map>('app_settings');
    _instance._backupsBox = await Hive.openBox<Map>('local_backups');
    _instance._syncMetadataBox = await Hive.openBox<Map>('sync_metadata');
    _instance._syncStateBox = await Hive.openBox<Map>('sync_state');
    _instance._onboardingBox = await Hive.openBox<bool>('onboarding');
    _instance._pendingBox = await Hive.openBox<Map>('pending_transactions');
    _instance._smsSeenBox = await Hive.openBox<bool>('sms_seen');
    // Device-local UI state (chat history, last tab) — deliberately excluded
    // from cloud snapshots and backups.
    await Hive.openBox(kLocalPrefsBox);
    _instance._initialized = true;
  }

  String _budgetKey(String userId, DateTime month) {
    final normalizedMonth = DateTime(month.year, month.month);
    return '$userId-${normalizedMonth.year}-${normalizedMonth.month}';
  }

  // Expense methods
  List<Expense> getAllExpenses(String userId) {
    if (!_initialized) return [];
    return _expensesBox.values
        .where((e) => _belongsToUser(e.userId, userId))
        .map(_hiveToExpense)
        .map((expense) => _normalizeLocalExpense(expense, userId))
        .toList();
  }

  Future<void> addExpense(Expense expense) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final hiveExpense = _expenseToHive(expense);
    await _expensesBox.put(expense.id, hiveExpense);
    await _markSyncPending(
      entityType: SyncEntityType.expense,
      entityId: expense.id,
      userId: expense.userId,
      updatedAt: expense.updatedAt ?? expense.createdAt,
      isDeleted: false,
    );
  }

  Future<void> updateExpense(String id, Expense expense) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final hiveExpense = _expenseToHive(expense);
    await _expensesBox.put(id, hiveExpense);
    await _markSyncPending(
      entityType: SyncEntityType.expense,
      entityId: id,
      userId: expense.userId,
      updatedAt: expense.updatedAt ?? DateTime.now(),
      isDeleted: false,
    );
  }

  Future<void> deleteExpense(String id) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final existing = _expensesBox.get(id);
    await _expensesBox.delete(id);
    if (existing != null) {
      await _markSyncPending(
        entityType: SyncEntityType.expense,
        entityId: id,
        userId: existing.userId,
        updatedAt: existing.updatedAt ?? existing.createdAt,
        isDeleted: true,
      );
    }
  }

  // Receivable methods
  List<Receivable> getAllReceivables(String userId) {
    if (!_initialized) return [];
    return _receivablesBox.values
        .where((r) => _belongsToUser(r.userId, userId))
        .map(_hiveToReceivable)
        .map((receivable) => _normalizeLocalReceivable(receivable, userId))
        .toList();
  }

  Future<void> addReceivable(Receivable receivable) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final hiveReceivable = _receivableToHive(receivable);
    await _receivablesBox.put(receivable.id, hiveReceivable);
    await _markSyncPending(
      entityType: SyncEntityType.receivable,
      entityId: receivable.id,
      userId: receivable.userId,
      updatedAt: receivable.updatedAt ?? receivable.createdAt,
      isDeleted: false,
    );
  }

  Future<void> updateReceivable(String id, Receivable receivable) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final hiveReceivable = _receivableToHive(receivable);
    await _receivablesBox.put(id, hiveReceivable);
    await _markSyncPending(
      entityType: SyncEntityType.receivable,
      entityId: id,
      userId: receivable.userId,
      updatedAt: receivable.updatedAt ?? DateTime.now(),
      isDeleted: false,
    );
  }

  Future<void> deleteReceivable(String id) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final existing = _receivablesBox.get(id);
    await _receivablesBox.delete(id);
    if (existing != null) {
      await _markSyncPending(
        entityType: SyncEntityType.receivable,
        entityId: id,
        userId: existing.userId,
        updatedAt: existing.updatedAt ?? existing.createdAt,
        isDeleted: true,
      );
    }
  }

  // Payable methods
  List<Payable> getAllPayables(String userId) {
    if (!_initialized) return [];
    return _payablesBox.values
        .where(
          (entry) => _belongsToUser(entry['userId'] as String? ?? '', userId),
        )
        .map(Payable.fromJson)
        .map((payable) => _normalizeLocalPayable(payable, userId))
        .toList();
  }

  Future<void> addPayable(Payable payable) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _payablesBox.put(payable.id, payable.toJson());
    await _markSyncPending(
      entityType: SyncEntityType.payable,
      entityId: payable.id,
      userId: payable.userId,
      updatedAt: payable.updatedAt ?? payable.createdAt,
      isDeleted: false,
    );
  }

  Future<void> updatePayable(String id, Payable payable) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _payablesBox.put(id, payable.toJson());
    await _markSyncPending(
      entityType: SyncEntityType.payable,
      entityId: id,
      userId: payable.userId,
      updatedAt: payable.updatedAt ?? DateTime.now(),
      isDeleted: false,
    );
  }

  Future<void> deletePayable(String id) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final existing = _payablesBox.get(id);
    await _payablesBox.delete(id);
    if (existing != null) {
      final existingPayable = Payable.fromJson(existing);
      await _markSyncPending(
        entityType: SyncEntityType.payable,
        entityId: id,
        userId: existingPayable.userId,
        updatedAt: existingPayable.updatedAt ?? existingPayable.createdAt,
        isDeleted: true,
      );
    }
  }

  // Monthly budget methods
  double getMonthlyBudget(String userId, DateTime month) {
    if (!_initialized) return 0.0;
    return _monthlyBudgetsBox.get(_budgetKey(userId, month)) ?? 0.0;
  }

  Future<void> setMonthlyBudget(
    String userId,
    DateTime month,
    double amount,
  ) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _monthlyBudgetsBox.put(_budgetKey(userId, month), amount);
    _notifyChanged();
  }

  Future<void> resetMonthlyBudget(String userId, DateTime month) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _monthlyBudgetsBox.delete(_budgetKey(userId, month));
    _notifyChanged();
  }

  // Recurring expense templates
  List<RecurringExpenseTemplate> getRecurringTemplates(String userId) {
    if (!_initialized) return [];

    return _recurringTemplatesBox.values
        .where(
          (template) =>
              _belongsToUser(template['userId'] as String? ?? '', userId),
        )
        .map(RecurringExpenseTemplate.fromJson)
        .map((template) => _normalizeLocalTemplate(template, userId))
        .toList();
  }

  Future<void> addRecurringTemplate(RecurringExpenseTemplate template) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _recurringTemplatesBox.put(template.id, template.toJson());
    await _markSyncPending(
      entityType: SyncEntityType.recurringTemplate,
      entityId: template.id,
      userId: template.userId,
      updatedAt: template.updatedAt ?? template.createdAt,
      isDeleted: false,
    );
  }

  Future<void> updateRecurringTemplate(
    String id,
    RecurringExpenseTemplate template,
  ) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _recurringTemplatesBox.put(id, template.toJson());
    await _markSyncPending(
      entityType: SyncEntityType.recurringTemplate,
      entityId: id,
      userId: template.userId,
      updatedAt: template.updatedAt ?? DateTime.now(),
      isDeleted: false,
    );
  }

  Future<void> deleteRecurringTemplate(String id) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final existing = _recurringTemplatesBox.get(id);
    await _recurringTemplatesBox.delete(id);
    if (existing != null) {
      final template = RecurringExpenseTemplate.fromJson(
        Map<dynamic, dynamic>.from(existing),
      );
      await _markSyncPending(
        entityType: SyncEntityType.recurringTemplate,
        entityId: id,
        userId: template.userId,
        updatedAt: template.updatedAt ?? template.createdAt,
        isDeleted: true,
      );
    }
  }

  Future<void> applyExpenseFromSync(Expense expense) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _expensesBox.put(expense.id, _expenseToHive(expense));
    await saveSyncMetadata(
      SyncMetadata(
        entityId: expense.id,
        entityType: SyncEntityType.expense,
        userId: expense.userId,
        updatedAt: expense.updatedAt ?? expense.createdAt,
        syncedAt: DateTime.now(),
        isDeleted: false,
        deviceId: getDeviceId(),
      ),
    );
  }

  Future<void> applyExpenseDeletionFromSync({
    required String id,
    required String userId,
    required DateTime updatedAt,
  }) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _expensesBox.delete(id);
    await saveSyncMetadata(
      SyncMetadata(
        entityId: id,
        entityType: SyncEntityType.expense,
        userId: userId,
        updatedAt: updatedAt,
        syncedAt: DateTime.now(),
        isDeleted: true,
        deviceId: getDeviceId(),
      ),
    );
  }

  Future<void> applyReceivableFromSync(Receivable receivable) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _receivablesBox.put(receivable.id, _receivableToHive(receivable));
    await saveSyncMetadata(
      SyncMetadata(
        entityId: receivable.id,
        entityType: SyncEntityType.receivable,
        userId: receivable.userId,
        updatedAt: receivable.updatedAt ?? receivable.createdAt,
        syncedAt: DateTime.now(),
        isDeleted: false,
        deviceId: getDeviceId(),
      ),
    );
  }

  Future<void> applyReceivableDeletionFromSync({
    required String id,
    required String userId,
    required DateTime updatedAt,
  }) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _receivablesBox.delete(id);
    await saveSyncMetadata(
      SyncMetadata(
        entityId: id,
        entityType: SyncEntityType.receivable,
        userId: userId,
        updatedAt: updatedAt,
        syncedAt: DateTime.now(),
        isDeleted: true,
        deviceId: getDeviceId(),
      ),
    );
  }

  Future<void> applyPayableFromSync(Payable payable) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _payablesBox.put(payable.id, payable.toJson());
    await saveSyncMetadata(
      SyncMetadata(
        entityId: payable.id,
        entityType: SyncEntityType.payable,
        userId: payable.userId,
        updatedAt: payable.updatedAt ?? payable.createdAt,
        syncedAt: DateTime.now(),
        isDeleted: false,
        deviceId: getDeviceId(),
      ),
    );
  }

  Future<void> applyPayableDeletionFromSync({
    required String id,
    required String userId,
    required DateTime updatedAt,
  }) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _payablesBox.delete(id);
    await saveSyncMetadata(
      SyncMetadata(
        entityId: id,
        entityType: SyncEntityType.payable,
        userId: userId,
        updatedAt: updatedAt,
        syncedAt: DateTime.now(),
        isDeleted: true,
        deviceId: getDeviceId(),
      ),
    );
  }

  Future<void> applyRecurringTemplateFromSync(
    RecurringExpenseTemplate template,
  ) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _recurringTemplatesBox.put(template.id, template.toJson());
    await saveSyncMetadata(
      SyncMetadata(
        entityId: template.id,
        entityType: SyncEntityType.recurringTemplate,
        userId: template.userId,
        updatedAt: template.updatedAt ?? template.createdAt,
        syncedAt: DateTime.now(),
        isDeleted: false,
        deviceId: getDeviceId(),
      ),
    );
  }

  Future<void> applyRecurringTemplateDeletionFromSync({
    required String id,
    required String userId,
    required DateTime updatedAt,
  }) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _recurringTemplatesBox.delete(id);
    await saveSyncMetadata(
      SyncMetadata(
        entityId: id,
        entityType: SyncEntityType.recurringTemplate,
        userId: userId,
        updatedAt: updatedAt,
        syncedAt: DateTime.now(),
        isDeleted: true,
        deviceId: getDeviceId(),
      ),
    );
  }

  // Settings
  Map<String, dynamic> getSettings(String userId) {
    if (!_initialized) return <String, dynamic>{};
    final data = _settingsBox.get(userId);
    if (data == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(data);
  }

  Future<void> saveSettings(String userId, Map<String, dynamic> values) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _settingsBox.put(userId, values);
    _notifyChanged();
  }

  // Custom expense categories (stored inside the per-user settings map).
  List<ExpenseCategory> getCustomCategories(String userId) {
    final settings = getSettings(userId);
    final raw = settings['categories'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map(ExpenseCategory.fromJson).toList();
  }

  Future<void> saveCustomCategories(
    String userId,
    List<ExpenseCategory> categories,
  ) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final settings = getSettings(userId);
    settings['categories'] = categories.map((c) => c.toJson()).toList();
    await saveSettings(userId, settings);
  }

  /// Payment methods the user can pick from. Empty means "never customised" —
  /// the notifier seeds the defaults. Stored beside categories in the settings
  /// map, so it rides the backup snapshot without touching the sync code.
  List<String> getPaymentMethods(String userId) {
    final raw = getSettings(userId)['paymentMethods'];
    if (raw is! List) return [];
    return raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<void> savePaymentMethods(String userId, List<String> methods) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final settings = getSettings(userId);
    settings['paymentMethods'] = methods;
    await saveSettings(userId, settings);
  }

  List<CycleHistorySnapshot> getCycleHistory(String userId) {
    final settings = getSettings(userId);
    final raw = settings['cycleHistory'];
    if (raw is! List) return [];
    final snapshots = raw
        .whereType<Map>()
        .map(CycleHistorySnapshot.fromJson)
        .toList();
    snapshots.sort((a, b) => b.cycleStartDate.compareTo(a.cycleStartDate));
    return snapshots;
  }

  Future<void> addCycleHistorySnapshot(
    String userId,
    CycleHistorySnapshot snapshot,
  ) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final settings = getSettings(userId);
    final existing = getCycleHistory(userId);
    final next = [snapshot, ...existing].take(36).toList();
    settings['cycleHistory'] = next.map((entry) => entry.toJson()).toList();
    await saveSettings(userId, settings);
  }

  CycleHistorySnapshot createCycleHistorySnapshot({
    required String userId,
    required DateTime cycleStartDate,
    required DateTime newCycleStartDate,
    required double cycleBudget,
    required double cycleSalary,
  }) {
    final normalizedStart = _startOfDay(cycleStartDate);
    final normalizedNewStart = _startOfDay(newCycleStartDate);
    final cycleExpenses = getAllExpenses(userId)
      ..sort((a, b) => b.date.compareTo(a.date));
    final filteredExpenses = cycleExpenses
        .where(
          (expense) =>
              !expense.date.isBefore(normalizedStart) &&
              expense.date.isBefore(normalizedNewStart),
        )
        .toList();

    final totalExpenses = filteredExpenses.fold<double>(
      0.0,
      (sum, expense) => sum + expense.amount,
    );
    final categoryBreakdown = <String, double>{};
    for (final expense in filteredExpenses) {
      categoryBreakdown[expense.category] =
          (categoryBreakdown[expense.category] ?? 0.0) + expense.amount;
    }

    final displayEndDate = normalizedNewStart.subtract(const Duration(days: 1));

    return CycleHistorySnapshot(
      id: 'cycle_${normalizedStart.millisecondsSinceEpoch}',
      userId: userId,
      cycleStartDate: normalizedStart,
      cycleEndDate: _startOfDay(displayEndDate),
      archivedAt: DateTime.now(),
      totalExpenses: totalExpenses,
      cycleBudget: cycleBudget,
      cycleSalary: cycleSalary,
      categoryBreakdown: categoryBreakdown,
      expenses: filteredExpenses
          .map(
            (expense) => CycleHistoryExpenseEntry(
              id: expense.id,
              category: expense.category,
              description: expense.description,
              amount: expense.amount,
              date: expense.date,
            ),
          )
          .toList(),
    );
  }

  String getDeviceId() {
    if (!_initialized) return 'uninitialized-device';
    final existing = _settingsBox.get(_syncDeviceIdKey);
    if (existing != null) {
      final deviceId = existing['value'] as String?;
      if (deviceId != null && deviceId.isNotEmpty) {
        return deviceId;
      }
    }
    final deviceId = 'device_${DateTime.now().microsecondsSinceEpoch}';
    _settingsBox.put(_syncDeviceIdKey, {'value': deviceId});
    return deviceId;
  }

  List<Map<String, dynamic>> getExportHistory(String userId) {
    final settings = getSettings(userId);
    final raw = settings['exportHistory'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> addExportHistoryEntry(
    String userId,
    Map<String, dynamic> entry,
  ) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final settings = getSettings(userId);
    final existing = getExportHistory(userId);
    final next = [entry, ...existing].take(12).toList();
    settings['exportHistory'] = next;
    await saveSettings(userId, settings);
  }

  List<SyncMetadata> getSyncMetadataForUser(String userId) {
    if (!_initialized) return [];
    return _syncMetadataBox.values
        .where((entry) => entry['userId'] == userId)
        .map(SyncMetadata.fromJson)
        .toList();
  }

  Future<void> saveSyncMetadata(SyncMetadata metadata) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final key = _syncKey(
      metadata.userId,
      metadata.entityType,
      metadata.entityId,
    );
    await _syncMetadataBox.put(key, metadata.toJson());
  }

  SyncState getSyncState(String userId) {
    if (!_initialized) return const SyncState();
    final raw = _syncStateBox.get(userId);
    if (raw == null) return const SyncState();
    return SyncState.fromJson(raw);
  }

  Future<void> saveSyncState(String userId, SyncState state) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _syncStateBox.put(userId, state.toJson());
  }

  // Onboarding
  bool isOnboardingCompleted() {
    if (!_initialized) return false;
    return _onboardingBox.get('completed') ?? false;
  }

  Future<void> setOnboardingCompleted(bool completed) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _onboardingBox.put('completed', completed);
  }

  // Pending SMS-detected transactions
  List<PendingTransaction> getPendingTransactions() {
    if (!_initialized) return [];
    return _pendingBox.values.map(PendingTransaction.fromJson).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  Future<void> savePendingTransaction(PendingTransaction txn) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    await _pendingBox.put(txn.id, txn.toJson());
    // Deliberately does NOT mark the account dirty. Detections sync through
    // detected_transactions, not the snapshot — and marking dirty here meant
    // that merely *receiving* a detection made the device look like it had
    // unpushed edits, so every later sync pushed instead of pulling and the
    // device silently stopped accepting other devices' expenses.
    // Only real money edits (addExpense and friends) may set that flag.
  }

  /// Fold another device's detected-SMS state into this one before a push.
  /// Whole-snapshot last-write-wins would otherwise drop pending items this
  /// device never pulled (phone detects an SMS while you're active on web →
  /// web's next push clobbers it). Union by id; a terminal status (added /
  /// dismissed) beats pending. Returns true if anything changed locally.
  ///
  /// Deliberately does NOT go through _notifyChanged: the caller pushes the
  /// merged snapshot immediately, and merged-in remote data isn't a local
  /// edit.
  Future<bool> mergeRemotePending(Map<String, dynamic> snapshot) async {
    if (!_initialized) return false;
    var changed = false;
    final remotePending = snapshot['pendingTransactions'];
    if (remotePending is List) {
      for (final entry in remotePending.whereType<Map>()) {
        final map = Map<String, dynamic>.from(entry);
        final id = map['id'];
        if (id is! String) continue;
        final local = _pendingBox.get(id);
        if (local == null) {
          await _pendingBox.put(id, map);
          changed = true;
        } else if (local['status'] == PendingStatus.pending.name &&
            map['status'] != PendingStatus.pending.name) {
          // The other device already added or dismissed it.
          await _pendingBox.put(id, map);
          changed = true;
        }
      }
    }
    // Union the seen-hash set so neither device re-parses the other's SMS.
    final remoteSeen = snapshot['smsSeen'];
    if (remoteSeen is Map) {
      for (final key in remoteSeen.keys) {
        final hash = '$key';
        if (!(_smsSeenBox.get(hash) ?? false)) {
          await _smsSeenBox.put(hash, true);
        }
      }
    }
    return changed;
  }

  /// Have we already run this SMS (by hash) through the parse pipeline?
  bool isSmsSeen(String hash) {
    if (!_initialized) return false;
    return _smsSeenBox.get(hash) ?? false;
  }

  Future<void> markSmsSeen(String hash) async {
    if (!_initialized) return;
    await _smsSeenBox.put(hash, true);
  }

  // Backup foundation
  Map<String, dynamic> createLocalBackupSnapshot(String userId) {
    // A restore clears each box before refilling it. Snapshotting during that
    // window captures a half-empty store, and uploading THAT is how a sync
    // race erased data. Callers must wait for the restore to finish.
    if (_restoring) {
      throw StateError(
        'Cannot snapshot while a restore is in progress (data would be '
        'incomplete). Retry the sync once it finishes.',
      );
    }
    final now = DateTime.now();
    final expenses = getAllExpenses(userId).map(_expenseToMap).toList();
    final receivables = getAllReceivables(
      userId,
    ).map(_receivableToMap).toList();
    final payables = getAllPayables(userId).map(_payableToMap).toList();
    final recurring = getRecurringTemplates(
      userId,
    ).map((template) => template.toJson()).toList();
    final settings = getSettings(userId);
    final monthBudget =
        (settings['currentCycleBudget'] as num?)?.toDouble() ??
        getMonthlyBudget(userId, now);
    // Everything else in local storage, so a restore is a true clone.
    final pending = _pendingBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final smsSeen = <String, bool>{
      for (final key in _smsSeenBox.keys) '$key': _smsSeenBox.get(key) ?? true,
    };
    final monthlyBudgets = <String, double>{
      for (final key in _monthlyBudgetsBox.keys)
        '$key': _monthlyBudgetsBox.get(key) ?? 0.0,
    };

    return {
      'backupId': 'backup_${now.millisecondsSinceEpoch}',
      'createdAt': now.toIso8601String(),
      'userId': userId,
      'monthlyBudget': monthBudget,
      'monthlyBudgets': monthlyBudgets,
      // NOTE: `settings` already carries cycle history, categories, cycle
      // budget/salary and export history, so previous cycles are included here.
      'settings': settings,
      'expenses': expenses,
      'receivables': receivables,
      'payables': payables,
      'recurringTemplates': recurring,
      'pendingTransactions': pending,
      'smsSeen': smsSeen,
      'onboardingCompleted': isOnboardingCompleted(),
    };
  }

  Future<void> saveLocalBackup(Map<String, dynamic> snapshot) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final backupId = snapshot['backupId'] as String;
    await _backupsBox.put(backupId, snapshot);
  }

  List<Map<String, dynamic>> getLocalBackups() {
    if (!_initialized) return [];
    return _backupsBox.values
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList()
      ..sort(
        (a, b) =>
            (b['createdAt'] as String).compareTo(a['createdAt'] as String),
      );
  }

  Map<String, dynamic>? getLocalBackupById(String backupId) {
    if (!_initialized) return null;
    final raw = _backupsBox.get(backupId);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw);
  }

  Future<void> restoreFromBackup(Map<String, dynamic> snapshot) async {
    if (!_initialized) throw Exception('HiveService not initialized');
    final userId = snapshot['userId'] as String?;
    if (userId == null || userId.isEmpty) {
      throw Exception('Invalid backup payload');
    }

    final currentSafetySnapshot = createLocalBackupSnapshot(userId);
    _restoring = true;
    try {
      await _restoreFromBackupUnsafe(snapshot, userId: userId);
    } catch (e) {
      // Best-effort rollback to reduce corruption risk.
      try {
        await _restoreFromBackupUnsafe(currentSafetySnapshot, userId: userId);
      } catch (_) {}
      rethrow;
    } finally {
      _restoring = false;
    }
  }

  Future<void> _restoreFromBackupUnsafe(
    Map<String, dynamic> snapshot, {
    required String userId,
  }) async {
    final expensesRaw = snapshot['expenses'];
    final receivablesRaw = snapshot['receivables'];
    final recurringRaw = snapshot['recurringTemplates'];
    final payablesRaw = snapshot['payables'];
    if (expensesRaw is! List ||
        receivablesRaw is! List ||
        recurringRaw is! List) {
      throw Exception('Invalid backup payload: missing lists');
    }

    final expenses = expensesRaw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .map(_expenseFromMap)
        .toList();
    final receivables = receivablesRaw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .map(_receivableFromMap)
        .toList();
    final recurringTemplates = recurringRaw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .map((m) => RecurringExpenseTemplate.fromJson(m))
        .toList();
    final payablesList = payablesRaw is List ? payablesRaw : <dynamic>[];
    final payables = payablesList
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .map((m) => Payable.fromJson(m))
        .toList();

    final settingsRaw = snapshot['settings'];
    final settings = settingsRaw is Map
        ? Map<String, dynamic>.from(settingsRaw)
        : <String, dynamic>{};

    final monthlyBudget = snapshot['monthlyBudget'];
    final monthlyBudgetValue = monthlyBudget is num
        ? monthlyBudget.toDouble()
        : 0.0;

    // Clear existing data before restore (single-user app today).
    await _expensesBox.clear();
    await _receivablesBox.clear();
    await _recurringTemplatesBox.clear();
    await _payablesBox.clear();
    await _settingsBox.delete(userId);
    await _monthlyBudgetsBox.clear();

    for (final expense in expenses) {
      await _expensesBox.put(expense.id, _expenseToHive(expense));
    }
    for (final receivable in receivables) {
      await _receivablesBox.put(receivable.id, _receivableToHive(receivable));
    }
    for (final template in recurringTemplates) {
      await _recurringTemplatesBox.put(template.id, template.toJson());
    }
    for (final payable in payables) {
      await _payablesBox.put(payable.id, payable.toJson());
    }
    if (settings.isNotEmpty) {
      await _settingsBox.put(userId, settings);
    }

    // Full monthly-budget history (new backups); fall back to the single
    // current-month value from older backups.
    final monthlyBudgetsRaw = snapshot['monthlyBudgets'];
    if (monthlyBudgetsRaw is Map) {
      for (final entry in monthlyBudgetsRaw.entries) {
        final value = entry.value;
        if (value is num) {
          await _monthlyBudgetsBox.put(entry.key.toString(), value.toDouble());
        }
      }
    } else if (monthlyBudgetValue > 0) {
      await setMonthlyBudget(userId, DateTime.now(), monthlyBudgetValue);
    }

    // Detected-SMS pending list + the seen-hashes dedup set. Rows are never
    // deleted (only status-changed), so a local row the snapshot has never
    // heard of is a fresh detection this device hasn't pushed yet — keep it
    // rather than losing it to the restore.
    final localOnlyPending = <String, Map<String, dynamic>>{};
    final pendingRaw = snapshot['pendingTransactions'];
    final snapshotIds = pendingRaw is List
        ? pendingRaw.whereType<Map>().map((e) => '${e['id']}').toSet()
        : const <String>{};
    for (final entry in _pendingBox.values) {
      final map = Map<String, dynamic>.from(entry);
      final id = map['id'];
      if (id is String && !snapshotIds.contains(id)) {
        localOnlyPending[id] = map;
      }
    }
    await _pendingBox.clear();
    if (pendingRaw is List) {
      for (final entry in pendingRaw.whereType<Map>()) {
        final map = Map<String, dynamic>.from(entry);
        await _pendingBox.put(map['id'], map);
      }
    }
    for (final entry in localOnlyPending.entries) {
      await _pendingBox.put(entry.key, entry.value);
    }
    // Seen hashes: union instead of replace, for the same reason.
    final smsSeenRaw = snapshot['smsSeen'];
    if (smsSeenRaw is Map) {
      for (final entry in smsSeenRaw.entries) {
        if (entry.value == true) {
          await _smsSeenBox.put(entry.key.toString(), true);
        }
      }
    }

    final onboarding = snapshot['onboardingCompleted'];
    if (onboarding is bool) {
      await setOnboardingCompleted(onboarding);
    }
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  Expense _expenseFromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as String,
      userId: map['userId'] as String? ?? '',
      amount: (map['amount'] as num).toDouble(),
      category: map['category'] as String? ?? 'Other',
      description: map['description'] as String?,
      date: DateTime.parse(map['date'] as String),
      paymentMethod: map['paymentMethod'] as String?,
      recurringTemplateId: map['recurringTemplateId'] as String?,
      recurringDueDate: map['recurringDueDate'] == null
          ? null
          : DateTime.tryParse(map['recurringDueDate'] as String),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.tryParse(map['updatedAt'] as String),
    );
  }

  Receivable _receivableFromMap(Map<String, dynamic> map) {
    return Receivable(
      id: map['id'] as String,
      userId: map['userId'] as String? ?? '',
      fromPerson: map['fromPerson'] as String? ?? 'Unknown',
      amount: (map['amount'] as num).toDouble(),
      description: map['description'] as String?,
      dueDate: DateTime.parse(map['dueDate'] as String),
      isPaid: map['isPaid'] as bool? ?? false,
      sourceExpenseId: map['sourceExpenseId'] as String?,
      remainingAmount: (map['remainingAmount'] as num?)?.toDouble(),
      settlements:
          (map['settlements'] as List?)
              ?.whereType<Map>()
              .map(ReceivableSettlement.fromJson)
              .toList() ??
          const [],
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.tryParse(map['updatedAt'] as String),
    );
  }

  // Conversion methods
  Expense _hiveToExpense(ExpenseHive hive) {
    return Expense(
      id: hive.id,
      userId: hive.userId,
      amount: hive.amount,
      category: hive.category,
      description: hive.description,
      date: hive.date,
      paymentMethod: hive.paymentMethod,
      recurringTemplateId: hive.recurringTemplateId,
      recurringDueDate: hive.recurringDueDate,
      createdAt: hive.createdAt,
      updatedAt: hive.updatedAt,
    );
  }

  ExpenseHive _expenseToHive(Expense expense) {
    return ExpenseHive(
      id: expense.id,
      userId: expense.userId,
      amount: expense.amount,
      category: expense.category,
      description: expense.description,
      date: expense.date,
      paymentMethod: expense.paymentMethod,
      recurringTemplateId: expense.recurringTemplateId,
      recurringDueDate: expense.recurringDueDate,
      createdAt: expense.createdAt,
      updatedAt: expense.updatedAt,
    );
  }

  Map<String, dynamic> _payableToMap(Payable payable) {
    return payable.toJson();
  }

  String _syncKey(String userId, SyncEntityType entityType, String entityId) {
    return '$userId::${entityType.name}::$entityId';
  }

  Future<void> _markSyncPending({
    required SyncEntityType entityType,
    required String entityId,
    required String userId,
    required DateTime updatedAt,
    required bool isDeleted,
  }) async {
    if (!_initialized) return;
    final metadata = SyncMetadata(
      entityId: entityId,
      entityType: entityType,
      userId: userId,
      updatedAt: updatedAt,
      syncedAt: null,
      isDeleted: isDeleted,
      deviceId: getDeviceId(),
    );
    await saveSyncMetadata(metadata);
    _notifyChanged();
  }

  Receivable _hiveToReceivable(ReceivableHive hive) {
    return Receivable(
      id: hive.id,
      userId: hive.userId,
      fromPerson: hive.fromPerson,
      amount: hive.amount,
      description: hive.description,
      dueDate: hive.dueDate,
      isPaid: hive.isPaid,
      sourceExpenseId: hive.sourceExpenseId,
      remainingAmount: hive.remainingAmount,
      settlements: _decodeReceivableSettlements(hive.settlementsJson),
      createdAt: hive.createdAt,
      updatedAt: hive.updatedAt,
    );
  }

  ReceivableHive _receivableToHive(Receivable receivable) {
    return ReceivableHive(
      id: receivable.id,
      userId: receivable.userId,
      fromPerson: receivable.fromPerson,
      amount: receivable.amount,
      description: receivable.description,
      dueDate: receivable.dueDate,
      isPaid: receivable.isPaid,
      sourceExpenseId: receivable.sourceExpenseId,
      remainingAmount: receivable.remainingAmount,
      settlementsJson: _encodeReceivableSettlements(receivable.settlements),
      createdAt: receivable.createdAt,
      updatedAt: receivable.updatedAt,
    );
  }

  Map<String, dynamic> _expenseToMap(Expense expense) {
    return {
      'id': expense.id,
      'userId': expense.userId,
      'amount': expense.amount,
      'category': expense.category,
      'description': expense.description,
      'date': expense.date.toIso8601String(),
      'paymentMethod': expense.paymentMethod,
      'recurringTemplateId': expense.recurringTemplateId,
      'recurringDueDate': expense.recurringDueDate?.toIso8601String(),
      'createdAt': expense.createdAt.toIso8601String(),
      'updatedAt': expense.updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _receivableToMap(Receivable receivable) {
    return {
      'id': receivable.id,
      'userId': receivable.userId,
      'fromPerson': receivable.fromPerson,
      'amount': receivable.amount,
      'description': receivable.description,
      'dueDate': receivable.dueDate.toIso8601String(),
      'isPaid': receivable.isPaid,
      'sourceExpenseId': receivable.sourceExpenseId,
      'remainingAmount': receivable.remainingAmount,
      'settlements': receivable.settlements
          .map((sett) => sett.toJson())
          .toList(),
      'createdAt': receivable.createdAt.toIso8601String(),
      'updatedAt': receivable.updatedAt?.toIso8601String(),
    };
  }

  String? _encodeReceivableSettlements(List<ReceivableSettlement> settlements) {
    if (settlements.isEmpty) return null;
    return jsonEncode(settlements.map((sett) => sett.toJson()).toList());
  }

  List<ReceivableSettlement> _decodeReceivableSettlements(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.whereType<Map>().map(ReceivableSettlement.fromJson).toList();
  }

  /// Move all locally-created data (offline records under [from], typically
  /// `local_android_user`) onto a real account [to] the first time the user
  /// signs in, so their history isn't lost. Re-put keeps ids, marks each
  /// entity sync-pending so it uploads. Cheap no-op once nothing is left under
  /// [from], so it's safe to call on every sign-in.
  Future<void> reassignUserData(String from, String to) async {
    if (!_initialized || from == to || to.isEmpty) return;
    for (final e in getAllExpenses(from)) {
      await updateExpense(e.id, e.copyWith(userId: to));
    }
    for (final r in getAllReceivables(from)) {
      await updateReceivable(r.id, r.copyWith(userId: to));
    }
    for (final p in getAllPayables(from)) {
      await updatePayable(p.id, p.copyWith(userId: to));
    }
    for (final t in getRecurringTemplates(from)) {
      await updateRecurringTemplate(t.id, t.copyWith(userId: to));
    }
    // Monthly budgets are keyed `<userId>-<year>-<month>` — rekey the prefix.
    final budgetKeys = _monthlyBudgetsBox.keys
        .whereType<String>()
        .where((k) => k.startsWith('$from-'))
        .toList();
    for (final k in budgetKeys) {
      final amount = _monthlyBudgetsBox.get(k);
      if (amount == null) continue;
      await _monthlyBudgetsBox.put(k.replaceFirst('$from-', '$to-'), amount);
      await _monthlyBudgetsBox.delete(k);
    }
    // The settings map carries cycle budget/salary/history, display name,
    // categories… — move it too, unless the target already has its own.
    final fromSettings = _settingsBox.get(from);
    if (fromSettings != null && _settingsBox.get(to) == null) {
      await _settingsBox.put(to, fromSettings);
      await _settingsBox.delete(from);
    }
  }

  /// Merge one settings key without clobbering the rest (safe to call while
  /// the settings provider is still loading).
  Future<void> updateSetting(String userId, String key, dynamic value) async {
    if (!_initialized) return;
    final map = Map<String, dynamic>.from(_settingsBox.get(userId) ?? {});
    map[key] = value;
    await _settingsBox.put(userId, map);
  }

  static const _localDataOwnerKey = 'local_data_owner';

  /// The account id the current locally-keyed data belongs to, or '' when it
  /// was created purely offline and never tied to any account. Used at sign-in
  /// to avoid folding one account's data into a different account.
  String getLocalDataOwner() {
    if (!_initialized) return '';
    return (_settingsBox.get('_meta')?[_localDataOwnerKey] as String?) ?? '';
  }

  Future<void> setLocalDataOwner(String userId) async {
    if (!_initialized) return;
    final meta = Map<String, dynamic>.from(_settingsBox.get('_meta') ?? {});
    meta[_localDataOwnerKey] = userId;
    await _settingsBox.put('_meta', meta);
  }

  /// Does this user have any money data locally? (expenses/receivables/
  /// payables/recurring). Used to detect first-sign-in / account-switch cases.
  bool hasDataFor(String userId) {
    if (!_initialized) return false;
    return getAllExpenses(userId).isNotEmpty ||
        getAllReceivables(userId).isNotEmpty ||
        getAllPayables(userId).isNotEmpty ||
        getRecurringTemplates(userId).isNotEmpty;
  }

  /// Wipe all local money data + budgets + pending (e.g. switching to a fresh
  /// account that has no cloud snapshot yet). The previous account's data is
  /// safe in its own cloud (pushed on logout).
  Future<void> clearAllData() async {
    if (!_initialized) return;
    await _expensesBox.clear();
    await _receivablesBox.clear();
    await _recurringTemplatesBox.clear();
    await _payablesBox.clear();
    await _monthlyBudgetsBox.clear();
    await _pendingBox.clear();
  }

  bool _belongsToUser(String recordUserId, String userId) {
    return recordUserId == userId ||
        (userId == _localUserId && recordUserId.isEmpty);
  }

  Expense _normalizeLocalExpense(Expense expense, String userId) {
    if (userId == _localUserId && expense.userId.isEmpty) {
      return expense.copyWith(userId: userId);
    }
    return expense;
  }

  Receivable _normalizeLocalReceivable(Receivable receivable, String userId) {
    if (userId == _localUserId && receivable.userId.isEmpty) {
      return receivable.copyWith(userId: userId);
    }
    return receivable;
  }

  Payable _normalizeLocalPayable(Payable payable, String userId) {
    if (userId == _localUserId && payable.userId.isEmpty) {
      return payable.copyWith(userId: userId);
    }
    return payable;
  }

  RecurringExpenseTemplate _normalizeLocalTemplate(
    RecurringExpenseTemplate template,
    String userId,
  ) {
    if (userId == _localUserId && template.userId.isEmpty) {
      return template.copyWith(userId: userId);
    }
    return template;
  }
}
