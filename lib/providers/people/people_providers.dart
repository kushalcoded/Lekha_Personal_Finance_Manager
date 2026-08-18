import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/payable/payable_model.dart';
import '../../services/storage/hive_service.dart';
import '../auth/auth_provider.dart';
import '../storage/storage_providers.dart';

/// One person's history with you, for ranking the split suggestions.
class PersonUse {
  final String name;

  /// How many receivables/payables mention them.
  final int count;

  /// When you last recorded anything with them.
  final DateTime? lastUsed;

  const PersonUse({required this.name, required this.count, this.lastUsed});
}

/// Names you've tracked money with, most likely first.
///
/// Ranking, in order: pinned names (in the order you pinned them), then how
/// often you've split with someone, then how recently, then alphabetically so
/// the result is stable rather than dependent on map iteration. Hidden names
/// are dropped entirely.
///
/// Friend-paid splits now record everyone on the bill, not just the payer, so
/// people you mostly get paid *for* rank on the same footing. Splits saved
/// before that still count only their payer; pinning remains the escape hatch.
List<String> rankPeople(
  List<PersonUse> people, {
  List<String> pinned = const [],
  List<String> hidden = const [],
}) {
  final hiddenSet = hidden.map((n) => n.toLowerCase()).toSet();
  final pinnedOrder = <String, int>{
    for (var i = 0; i < pinned.length; i++) pinned[i].toLowerCase(): i,
  };

  final visible = people
      .where((p) => !hiddenSet.contains(p.name.toLowerCase()))
      .toList();

  visible.sort((a, b) {
    final aPin = pinnedOrder[a.name.toLowerCase()];
    final bPin = pinnedOrder[b.name.toLowerCase()];
    if (aPin != null || bPin != null) {
      if (aPin == null) return 1;
      if (bPin == null) return -1;
      return aPin.compareTo(bPin);
    }
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    final aWhen = a.lastUsed;
    final bWhen = b.lastUsed;
    if (aWhen != null && bWhen != null && aWhen != bWhen) {
      return bWhen.compareTo(aWhen);
    }
    if (aWhen == null && bWhen != null) return 1;
    if (bWhen == null && aWhen != null) return -1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return visible.map((p) => p.name).toList();
}

/// Everyone a payable puts you in touch with: the person you owe, plus anyone
/// else who was on the same bill. Each appears once — the payer is in
/// `participants` too, and counting them twice would rank one split as two.
List<String> payablePeople(Payable payable) => [
  payable.toPerson,
  ...payable.participants.keys.where(
    (name) => name.toLowerCase() != payable.toPerson.toLowerCase(),
  ),
];

/// Everyone you've already tracked money with, ranked for the split picker so
/// the people you actually split with are one tap away.
final knownPeopleProvider = Provider<List<String>>((ref) {
  final receivables = ref.watch(receivablesProvider).receivables;
  final payables = ref.watch(payablesProvider).payables;
  final prefs = ref.watch(peoplePrefsProvider);

  // Case-insensitive grouping, keeping the first spelling seen — "Ravi" and
  // "ravi" used to sit in the list as two different people.
  final byKey = <String, PersonUse>{};
  void record(String raw, DateTime? when) {
    final name = raw.trim();
    if (name.isEmpty) return;
    final key = name.toLowerCase();
    final existing = byKey[key];
    final latest = existing?.lastUsed == null
        ? when
        : (when != null && when.isAfter(existing!.lastUsed!)
              ? when
              : existing!.lastUsed);
    byKey[key] = PersonUse(
      name: existing?.name ?? name,
      count: (existing?.count ?? 0) + 1,
      lastUsed: latest,
    );
  }

  for (final r in receivables) {
    record(r.fromPerson, r.createdAt);
  }
  for (final p in payables) {
    for (final person in payablePeople(p)) {
      record(person, p.createdAt);
    }
  }

  return rankPeople(
    byKey.values.toList(),
    pinned: prefs.pinned,
    hidden: prefs.hidden,
  );
});

/// Manual overrides on the ranking: names you always want first, and names you
/// never want offered.
class PeoplePrefs {
  final List<String> pinned;
  final List<String> hidden;

  const PeoplePrefs({this.pinned = const [], this.hidden = const []});

  bool isPinned(String name) =>
      pinned.any((n) => n.toLowerCase() == name.toLowerCase());

  bool isHidden(String name) =>
      hidden.any((n) => n.toLowerCase() == name.toLowerCase());
}

final peoplePrefsProvider =
    StateNotifierProvider<PeoplePrefsNotifier, PeoplePrefs>((ref) {
      return PeoplePrefsNotifier(ref);
    });

class PeoplePrefsNotifier extends StateNotifier<PeoplePrefs> {
  final Ref _ref;

  PeoplePrefsNotifier(this._ref) : super(const PeoplePrefs()) {
    _load();
  }

  HiveService get _hive => _ref.read(hiveServiceProvider);
  String get _userId => _ref.read(currentUserIdProvider) ?? localUserId;

  void _load() {
    final raw = _hive.getSettings(_userId)['peoplePrefs'];
    if (raw is! Map) return;
    state = PeoplePrefs(
      pinned: _stringList(raw['pinned']),
      hidden: _stringList(raw['hidden']),
    );
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<void> _persist(PeoplePrefs next) async {
    state = next;
    final settings = _hive.getSettings(_userId);
    settings['peoplePrefs'] = {'pinned': next.pinned, 'hidden': next.hidden};
    await _hive.saveSettings(_userId, settings);
  }

  Future<void> togglePin(String name) async {
    final pinned = [...state.pinned];
    pinned.removeWhere((n) => n.toLowerCase() == name.toLowerCase());
    if (pinned.length == state.pinned.length) pinned.add(name.trim());
    // Pinning implies wanting to see them.
    final hidden = [...state.hidden]
      ..removeWhere((n) => n.toLowerCase() == name.toLowerCase());
    await _persist(PeoplePrefs(pinned: pinned, hidden: hidden));
  }

  Future<void> toggleHide(String name) async {
    final hidden = [...state.hidden];
    hidden.removeWhere((n) => n.toLowerCase() == name.toLowerCase());
    if (hidden.length == state.hidden.length) hidden.add(name.trim());
    final pinned = [...state.pinned]
      ..removeWhere((n) => n.toLowerCase() == name.toLowerCase());
    await _persist(PeoplePrefs(pinned: pinned, hidden: hidden));
  }
}

/// Everyone on record, including hidden names — for the manage screen, which
/// is the only way back from hiding someone.
final allKnownPeopleProvider = Provider<List<String>>((ref) {
  final receivables = ref.watch(receivablesProvider).receivables;
  final payables = ref.watch(payablesProvider).payables;
  final names = <String, String>{};
  for (final name in [
    ...receivables.map((r) => r.fromPerson.trim()),
    ...payables.map((p) => p.toPerson.trim()),
  ]) {
    if (name.isEmpty) continue;
    names.putIfAbsent(name.toLowerCase(), () => name);
  }
  final sorted = names.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return sorted;
});
