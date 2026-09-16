import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/storage/hive_service.dart';
import '../auth/auth_provider.dart';
import '../storage/storage_providers.dart';
import 'card_providers.dart';

/// What the app ships with. Only ever used to seed a brand-new user — after
/// that the stored list wins, including deletions.
///
/// Named after the instrument rather than the app: UPI covers GPay, PhonePe
/// and Paytm alike, and "Card" said nothing about whether the money had
/// already left your account. Anyone who prefers the app names can add them.
const defaultPaymentMethods = <String>[
  'UPI',
  'Net Banking',
  'Cash',
  'Debit Card',
  'Credit Card',
];

/// Labels that were renamed, not replaced. An existing list keeps its own
/// entries — deletions included — but these two named the same thing under an
/// older name, and leaving them behind would split one payment method into two
/// buckets in the breakdown.
const renamedPaymentMethods = <String, String>{
  'Bank Transfer': 'Net Banking',
  'Card': 'Credit Card',
};

/// What a stored list becomes on this version: the renames applied, in place,
/// and nothing else touched. Order is the user's — the list is drag-sortable —
/// and a method they deleted stays deleted.
List<String> upgradePaymentMethods(List<String> stored) {
  final taken = {for (final name in stored) name.toLowerCase()};
  return [
    for (final name in stored)
      if (renamedPaymentMethods[name] case final renamed?
          when !taken.contains(renamed.toLowerCase()))
        renamed
      else
        name,
  ];
}

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
    final upgraded = upgradePaymentMethods(stored);
    state = upgraded;
    if (!_sameList(stored, upgraded)) {
      // Renames carry the expenses with them, exactly as renaming by hand
      // would — otherwise the old label would vanish from the picker while
      // every expense still carried it.
      Future.microtask(() async {
        await _hive.savePaymentMethods(_userId, upgraded);
        for (var i = 0; i < stored.length; i++) {
          if (stored[i] != upgraded[i]) {
            await _migrate(stored[i], upgraded[i]);
            if (defaultFor(_userId) == stored[i]) {
              await setDefault(upgraded[i]);
            }
          }
        }
      });
    }
  }

  static bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length && !a.indexed.any((e) => e.$2 != b[e.$1]);

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
    // The default is stored by name, so renaming the starred method would
    // otherwise leave it pointing at a method that no longer exists.
    if (defaultFor(_userId) == from) await setDefault(trimmed);
    await _moveCard(from, trimmed);
    return true;
  }

  /// Card settings are keyed by method name, so a rename has to carry them and
  /// a removal has to drop them — the same name-keyed migration this class
  /// already does for expenses and the default.
  Future<void> _moveCard(String from, String? to) async {
    final cards = Map<String, Map<String, int?>>.from(_hive.getCards(_userId));
    final config = cards.remove(from);
    if (config == null) return;
    if (to != null) cards[to] = config;
    await _hive.saveCards(_userId, cards);
  }

  /// Mark a method as a credit card, or clear it. Statement and due day are
  /// optional — they only frame "this statement, due on the 5th"; the balance
  /// is a running total either way.
  Future<void> setCard(
    String method, {
    required bool isCard,
    int? statementDay,
    int? dueDay,
  }) async {
    final cards = Map<String, Map<String, int?>>.from(_hive.getCards(_userId));
    if (isCard) {
      cards[method] = {'statementDay': statementDay, 'dueDay': dueDay};
    } else {
      cards.remove(method);
    }
    await _hive.saveCards(_userId, cards);
    _ref.invalidate(cardsProvider);
  }

  Map<String, int?>? cardConfig(String method) =>
      _hive.getCards(_userId)[method];

  /// Remove a method from the picker. Expenses already tagged with it keep
  /// their label — the analytics panel groups by whatever is stored, so the
  /// history stays honest instead of silently re-bucketing.
  Future<void> remove(String name) async {
    await _persist(state.where((m) => m != name).toList());
    if (defaultFor(_userId) == name) {
      await setDefault(null);
    }
    await _moveCard(name, null);
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

  /// Carry every record using the old label across to the new one. Recurring
  /// templates keep their own copy of the method, so missing them here would
  /// leave future generated expenses tagged with a name that no longer exists.
  Future<void> _migrate(String from, String to) async {
    final userId = _userId;

    for (final expense in _hive.getAllExpenses(userId)) {
      if (expense.paymentMethod != from) continue;
      await _hive.updateExpense(
        expense.id,
        expense.copyWith(paymentMethod: to, updatedAt: DateTime.now()),
      );
    }
    for (final template in _hive.getRecurringTemplates(userId)) {
      if (template.paymentMethod != from) continue;
      await _hive.updateRecurringTemplate(
        template.id,
        template.copyWith(paymentMethod: to),
      );
    }

    _ref.read(expensesProvider.notifier).fetchExpenses(userId);
    _ref.read(recurringTemplatesProvider.notifier).fetchTemplates(userId);
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

/// The picker list, guaranteed to contain whatever the record being edited
/// already carries — even if that method has since been deleted. Without this,
/// opening an old expense or recurring template shows nothing selected and
/// saving silently retags it.
List<String> methodsIncluding(List<String> methods, String? current) {
  final trimmed = current?.trim();
  if (trimmed == null || trimmed.isEmpty) return methods;
  if (methods.any((m) => m.toLowerCase() == trimmed.toLowerCase())) {
    return methods;
  }
  return [...methods, trimmed];
}
