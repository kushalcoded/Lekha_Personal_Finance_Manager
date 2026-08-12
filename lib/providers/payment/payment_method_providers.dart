import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/expense/expense_model.dart';
import '../../services/storage/hive_service.dart';
import '../auth/auth_provider.dart';
import '../storage/storage_providers.dart';

/// What the app ships with. Only ever used to seed a brand-new user — after
/// that the stored list wins, including deletions.
const defaultPaymentMethods = <String>[
  'Cash',
  'GPay',
  'PhonePe',
  'Paytm',
  'Bank Transfer',
  'Card',
];

/// The user's payment methods, in their own order.
///
/// Before this existed the same six strings were hardcoded in three modals and
/// the analytics provider — two of them in a different order — so the list you
/// saw depended on which screen you were standing on.
final paymentMethodsProvider =
    StateNotifierProvider<PaymentMethodsNotifier, List<String>>((ref) {
      return PaymentMethodsNotifier(ref);
    });

class PaymentMethodsNotifier extends StateNotifier<List<String>> {
  final Ref _ref;

  PaymentMethodsNotifier(this._ref) : super(const []) {
    _load();
  }

  HiveService get _hive => _ref.read(hiveServiceProvider);
  String get _userId => _ref.read(currentUserIdProvider) ?? localUserId;

  void _load() {
    final stored = _hive.getPaymentMethods(_userId);
    if (stored.isEmpty) {
      state = List.of(defaultPaymentMethods);
      _hive.savePaymentMethods(_userId, state);
      return;
    }
    state = stored;
  }

  Future<void> _persist(List<String> methods) async {
    state = methods;
    await _hive.savePaymentMethods(_userId, methods);
  }

  bool exists(String name) {
    final target = name.trim().toLowerCase();
    return state.any((m) => m.toLowerCase() == target);
  }

  Future<bool> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || exists(trimmed)) return false;
    await _persist([...state, trimmed]);
    return true;
  }

  /// Rename, carrying every expense that used the old label across with it —
  /// otherwise the spend would drop out of the payment breakdown, which groups
  /// by the stored string.
  Future<bool> rename(String from, String to) async {
    final trimmed = to.trim();
    if (trimmed.isEmpty || from == trimmed) return false;
    if (exists(trimmed)) return false;
    final index = state.indexWhere((m) => m == from);
    if (index < 0) return false;

    final next = [...state]..[index] = trimmed;
    await _persist(next);
    await _migrate(from, trimmed);
    return true;
  }

  /// Remove a method from the picker. Expenses already tagged with it keep
  /// their label — the analytics panel groups by whatever is stored, so the
  /// history stays honest instead of silently re-bucketing.
  Future<void> remove(String name) async {
    await _persist(state.where((m) => m != name).toList());
    if (defaultFor(_userId) == name) {
      await setDefault(null);
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final next = [...state];
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    next.insert(target, next.removeAt(oldIndex));
    await _persist(next);
  }

  int usageCount(String method) {
    return _hive
        .getAllExpenses(_userId)
        .where((e) => e.paymentMethod == method)
        .length;
  }

  String? defaultFor(String userId) =>
      _hive.getSettings(userId)['defaultPaymentMethod'] as String?;

  /// The method preselected in the add sheet and used for expenses approved
  /// from a notification, where there is nobody to ask.
  Future<void> setDefault(String? method) async {
    final settings = _hive.getSettings(_userId);
    settings['defaultPaymentMethod'] = method;
    await _hive.saveSettings(_userId, settings);
    _ref.invalidate(defaultPaymentMethodProvider);
  }

  Future<void> _migrate(String from, String to) async {
    final expenses = _hive.getAllExpenses(_userId);
    for (final expense in expenses) {
      if (expense.paymentMethod != from) continue;
      await _hive.updateExpense(
        expense.id,
        expense.copyWith(paymentMethod: to, updatedAt: DateTime.now()),
      );
    }
    final userId = _userId;
    _ref.read(expensesProvider.notifier).fetchExpenses(userId);
  }
}

/// The user's default payment method, or null when they haven't picked one.
final defaultPaymentMethodProvider = Provider<String?>((ref) {
  // Watch the list so a delete that clears the default refreshes this too.
  ref.watch(paymentMethodsProvider);
  final hive = ref.read(hiveServiceProvider);
  final userId = ref.watch(currentUserIdProvider) ?? localUserId;
  final stored = hive.getSettings(userId)['defaultPaymentMethod'] as String?;
  if (stored == null || stored.trim().isEmpty) return null;
  return stored;
});

/// The method to tag an expense with when nobody can be asked — the
/// notification shade has no picker. Falls back to inference from the SMS.
String? resolveAutoPaymentMethod(String? preferred, String? inferred) {
  final chosen = preferred?.trim();
  if (chosen != null && chosen.isNotEmpty) return chosen;
  return inferred;
}

/// Convenience for surfaces that hold an [Expense] and want the picker list to
/// include whatever that expense already carries, even if the method was since
/// deleted — otherwise editing an old expense silently changes its method.
List<String> methodsIncluding(List<String> methods, Expense? expense) {
  final current = expense?.paymentMethod?.trim();
  if (current == null || current.isEmpty) return methods;
  if (methods.any((m) => m.toLowerCase() == current.toLowerCase())) {
    return methods;
  }
  return [...methods, current];
}
