import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/expense/expense_model.dart';
import '../../models/recurring/recurring_expense_template.dart';
import '../../models/receivable/receivable_model.dart';
import '../../models/payable/payable_model.dart';
import '../../services/storage/hive_service.dart';
import '../auth/auth_provider.dart';
import '../sync/sync_providers.dart';

final hiveServiceProvider = Provider((ref) {
  return HiveService();
});

class ExpensesState {
  final List<Expense> expenses;
  final bool isLoading;
  final String? error;

  const ExpensesState({
    this.expenses = const [],
    this.isLoading = false,
    this.error,
  });

  ExpensesState copyWith({
    List<Expense>? expenses,
    bool? isLoading,
    String? error,
  }) {
    return ExpensesState(
      expenses: expenses ?? this.expenses,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class ExpensesNotifier extends StateNotifier<ExpensesState> {
  final HiveService _hiveService;
  final Ref _ref;

  ExpensesNotifier(this._hiveService, this._ref) : super(const ExpensesState());

  Future<void> fetchExpenses(String userId) async {
    state = state.copyWith(isLoading: true);
    try {
      final expenses = _hiveService.getAllExpenses(userId);
      state = state.copyWith(expenses: expenses, isLoading: false, error: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> addExpense(Expense expense) async {
    try {
      await _hiveService.addExpense(expense);
      final updated = [...state.expenses, expense];
      state = state.copyWith(expenses: updated, error: null);
      // Trigger non-blocking sync
      _ref.read(syncProvider.notifier).syncNow();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> updateExpense(String id, Expense expense) async {
    try {
      await _hiveService.updateExpense(id, expense);
      final updated = state.expenses
          .map((e) => e.id == id ? expense : e)
          .toList();
      state = state.copyWith(expenses: updated, error: null);
      // Trigger non-blocking sync
      _ref.read(syncProvider.notifier).syncNow();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteExpense(String id) async {
    try {
      await _hiveService.deleteExpense(id);
      final updated = state.expenses.where((e) => e.id != id).toList();
      state = state.copyWith(expenses: updated, error: null);
      // Trigger non-blocking sync
      _ref.read(syncProvider.notifier).syncNow();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void refresh(String userId) {
    fetchExpenses(userId);
  }
}

final expensesProvider = StateNotifierProvider<ExpensesNotifier, ExpensesState>(
  (ref) {
    final hiveService = ref.watch(hiveServiceProvider);
    return ExpensesNotifier(hiveService, ref);
  },
);

final recentExpensesProvider = Provider.family<List<Expense>, String>((
  ref,
  userId,
) {
  final expenses = ref.watch(expensesProvider).expenses;
  return expenses.where((e) => e.userId == userId).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
});

final totalExpensesProvider = Provider.family<double, String>((ref, userId) {
  final expenses = ref.watch(expensesProvider).expenses;
  return expenses.fold(
    0.0,
    (sum, e) => sum + (e.userId == userId ? e.amount : 0),
  );
});

// Receivables
class ReceivablesState {
  final List<Receivable> receivables;
  final bool isLoading;
  final String? error;

  const ReceivablesState({
    this.receivables = const [],
    this.isLoading = false,
    this.error,
  });

  ReceivablesState copyWith({
    List<Receivable>? receivables,
    bool? isLoading,
    String? error,
  }) {
    return ReceivablesState(
      receivables: receivables ?? this.receivables,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class ReceivablesNotifier extends StateNotifier<ReceivablesState> {
  final HiveService _hiveService;
  final Ref _ref;

  ReceivablesNotifier(this._hiveService, this._ref)
    : super(const ReceivablesState());

  Future<void> fetchReceivables(String userId) async {
    state = state.copyWith(isLoading: true);
    try {
      final receivables = _hiveService.getAllReceivables(userId);
      state = state.copyWith(
        receivables: receivables,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> addReceivable(Receivable receivable) async {
    try {
      await _hiveService.addReceivable(receivable);
      final updated = [...state.receivables, receivable];
      state = state.copyWith(receivables: updated, error: null);
      // Trigger non-blocking sync
      _ref.read(syncProvider.notifier).syncNow();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> updateReceivable(String id, Receivable receivable) async {
    try {
      await _hiveService.updateReceivable(id, receivable);
      final updated = state.receivables
          .map((r) => r.id == id ? receivable : r)
          .toList();
      state = state.copyWith(receivables: updated, error: null);
      // Trigger non-blocking sync
      _ref.read(syncProvider.notifier).syncNow();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> markReceivablePaid(String id) async {
    final existing = _findReceivable(id);
    if (existing == null) return;
    await addReceivableSettlement(id, existing.remaining);
  }

  Receivable? _findReceivable(String id) {
    for (final r in state.receivables) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Record a (partial or full) repayment against one receivable.
  Future<void> addReceivableSettlement(
    String id,
    double amount, {
    String? note,
  }) async {
    final existing = _findReceivable(id);
    if (existing == null || amount <= 0) return;
    final settled = amount > existing.remaining ? existing.remaining : amount;
    final remaining = (existing.remaining - settled).clamp(0.0, double.infinity);
    final now = DateTime.now();
    final settlement = ReceivableSettlement(
      id: 'settle_${now.microsecondsSinceEpoch}',
      amount: settled,
      remainingAfter: remaining,
      note: (note == null || note.trim().isEmpty) ? null : note.trim(),
      settledAt: now,
    );
    await updateReceivable(
      id,
      existing.copyWith(
        remainingAmount: remaining,
        isPaid: remaining <= 0,
        settlements: [...existing.settlements, settlement],
        updatedAt: now,
      ),
    );
  }

  /// Apply a lump payment across [person]'s open receivables, oldest first.
  /// Returns any amount left over (they paid more than they owed you).
  Future<double> settlePersonReceivables(
    String person,
    double amount, {
    String? note,
  }) async {
    var left = amount;
    final open =
        state.receivables
            .where(
              (r) =>
                  r.fromPerson.toLowerCase() == person.toLowerCase() &&
                  r.remaining > 0,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final r in open) {
      if (left <= 0) break;
      final pay = left > r.remaining ? r.remaining : left;
      await addReceivableSettlement(r.id, pay, note: note);
      left -= pay;
    }
    return left;
  }

  Future<void> deleteReceivable(String id) async {
    try {
      await _hiveService.deleteReceivable(id);
      final updated = state.receivables.where((r) => r.id != id).toList();
      state = state.copyWith(receivables: updated, error: null);
      // Trigger non-blocking sync
      _ref.read(syncProvider.notifier).syncNow();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void refresh(String userId) {
    fetchReceivables(userId);
  }
}

final receivablesProvider =
    StateNotifierProvider<ReceivablesNotifier, ReceivablesState>((ref) {
      final hiveService = ref.watch(hiveServiceProvider);
      return ReceivablesNotifier(hiveService, ref);
    });

final recentReceivablesProvider = Provider.family<List<Receivable>, String>((
  ref,
  userId,
) {
  final receivables = ref.watch(receivablesProvider).receivables;
  return receivables.where((r) => r.userId == userId).toList()
    ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
});

final totalReceivablesProvider = Provider.family<double, String>((ref, userId) {
  final receivables = ref.watch(receivablesProvider).receivables;
  return receivables.fold(
    0.0,
    (sum, r) => sum + (r.userId == userId ? r.remaining : 0),
  );
});

// Payables
class PayablesState {
  final List<Payable> payables;
  final bool isLoading;
  final String? error;

  const PayablesState({
    this.payables = const [],
    this.isLoading = false,
    this.error,
  });

  PayablesState copyWith({
    List<Payable>? payables,
    bool? isLoading,
    String? error,
  }) {
    return PayablesState(
      payables: payables ?? this.payables,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class PayablesNotifier extends StateNotifier<PayablesState> {
  final HiveService _hiveService;
  final Ref _ref;

  PayablesNotifier(this._hiveService, this._ref) : super(const PayablesState());

  Future<void> fetchPayables(String userId) async {
    state = state.copyWith(isLoading: true);
    try {
      final payables = _hiveService.getAllPayables(userId);
      state = state.copyWith(payables: payables, isLoading: false, error: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> addPayable(Payable payable) async {
    try {
      await _hiveService.addPayable(payable);
      state = state.copyWith(
        payables: [...state.payables, payable],
        error: null,
      );
      // Trigger non-blocking sync
      _ref.read(syncProvider.notifier).syncNow();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> updatePayable(String id, Payable payable) async {
    try {
      await _hiveService.updatePayable(id, payable);
      final updated = state.payables
          .map((item) => item.id == id ? payable : item)
          .toList();
      state = state.copyWith(payables: updated, error: null);
      // Trigger non-blocking sync
      _ref.read(syncProvider.notifier).syncNow();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deletePayable(String id) async {
    try {
      await _hiveService.deletePayable(id);
      final updated = state.payables.where((item) => item.id != id).toList();
      state = state.copyWith(payables: updated, error: null);
      // Trigger non-blocking sync
      _ref.read(syncProvider.notifier).syncNow();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> markPayablePaid(String id, {String? note}) async {
    final existing = _findById(id);
    if (existing == null) return;
    await addSettlement(
      id,
      existing.remainingAmount,
      note: note,
      settledAt: DateTime.now(),
    );
  }

  Future<void> addSettlement(
    String id,
    double amount, {
    String? note,
    DateTime? settledAt,
  }) async {
    final existing = _findById(id);
    if (existing == null || amount <= 0) return;

    final next = _applySettlement(
      existing,
      amount: amount,
      note: note,
      settledAt: settledAt ?? DateTime.now(),
    );
    await updatePayable(id, next);
  }

  /// Apply a lump payment across [person]'s open payables, oldest first.
  Future<double> settlePersonPayables(
    String person,
    double amount, {
    String? note,
  }) async {
    var left = amount;
    final open =
        state.payables
            .where(
              (p) =>
                  p.toPerson.toLowerCase() == person.toLowerCase() &&
                  p.remainingAmount > 0,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final p in open) {
      if (left <= 0) break;
      final pay = left > p.remainingAmount ? p.remainingAmount : left;
      await addSettlement(p.id, pay, note: note);
      left -= pay;
    }
    return left;
  }

  Payable? _findById(String id) {
    for (final payable in state.payables) {
      if (payable.id == id) return payable;
    }
    return null;
  }

  Payable _applySettlement(
    Payable payable, {
    required double amount,
    String? note,
    required DateTime settledAt,
  }) {
    final settled = amount > payable.remainingAmount
        ? payable.remainingAmount
        : amount;
    final remaining = (payable.remainingAmount - settled).clamp(
      0.0,
      double.infinity,
    );
    final status = remaining <= 0
        ? PayableStatus.paid
        : (remaining < payable.amount
              ? PayableStatus.partial
              : PayableStatus.pending);
    final settlement = PayableSettlement(
      id: 'settle_${settledAt.microsecondsSinceEpoch}',
      amount: settled,
      remainingAfter: remaining,
      note: note?.trim().isEmpty ?? true ? null : note?.trim(),
      settledAt: settledAt,
    );
    return payable.copyWith(
      remainingAmount: remaining,
      status: status,
      settlements: [...payable.settlements, settlement],
      updatedAt: settledAt,
    );
  }
}

final payablesProvider = StateNotifierProvider<PayablesNotifier, PayablesState>(
  (ref) {
    final hiveService = ref.watch(hiveServiceProvider);
    return PayablesNotifier(hiveService, ref);
  },
);

final totalPayablesProvider = Provider.family<double, String>((ref, userId) {
  final payables = ref.watch(payablesProvider).payables;
  return payables.fold(
    0.0,
    (sum, item) => sum + (item.userId == userId ? item.remainingAmount : 0),
  );
});

class RecurringTemplatesState {
  final List<RecurringExpenseTemplate> templates;
  final bool isLoading;
  final String? error;

  const RecurringTemplatesState({
    this.templates = const [],
    this.isLoading = false,
    this.error,
  });

  RecurringTemplatesState copyWith({
    List<RecurringExpenseTemplate>? templates,
    bool? isLoading,
    String? error,
  }) {
    return RecurringTemplatesState(
      templates: templates ?? this.templates,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class RecurringTemplatesNotifier
    extends StateNotifier<RecurringTemplatesState> {
  final HiveService _hiveService;
  final Ref _ref;

  RecurringTemplatesNotifier(this._hiveService, this._ref)
    : super(const RecurringTemplatesState()) {
    final userId = _ref.read(currentUserIdProvider);
    if (userId != null && userId.isNotEmpty) {
      fetchTemplates(userId);
    }
  }

  Future<void> fetchTemplates(String userId) async {
    state = state.copyWith(isLoading: true);
    try {
      final templates = _hiveService.getRecurringTemplates(userId);
      state = state.copyWith(
        templates: templates,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> addTemplate(RecurringExpenseTemplate template) async {
    try {
      await _hiveService.addRecurringTemplate(template);
      state = state.copyWith(templates: [...state.templates, template]);
      // Trigger non-blocking sync
      _ref.read(syncProvider.notifier).syncNow();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> updateTemplate(
    String id,
    RecurringExpenseTemplate template,
  ) async {
    try {
      await _hiveService.updateRecurringTemplate(id, template);
      final updated = state.templates
          .map((existing) => existing.id == id ? template : existing)
          .toList();
      state = state.copyWith(templates: updated, error: null);
      // Trigger non-blocking sync
      _ref.read(syncProvider.notifier).syncNow();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteTemplate(String id) async {
    try {
      await _hiveService.deleteRecurringTemplate(id);
      final updated = state.templates.where((item) => item.id != id).toList();
      state = state.copyWith(templates: updated, error: null);
      // Trigger non-blocking sync
      _ref.read(syncProvider.notifier).syncNow();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

final recurringTemplatesProvider =
    StateNotifierProvider<RecurringTemplatesNotifier, RecurringTemplatesState>((
      ref,
    ) {
      final hiveService = ref.watch(hiveServiceProvider);
      return RecurringTemplatesNotifier(hiveService, ref);
    });
