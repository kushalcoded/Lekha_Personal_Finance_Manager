import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/expense/expense_model.dart';
import '../../models/share/shared_entry.dart';
import '../../screens/debts/providers/people_balance_providers.dart';
import '../../screens/debts/utils/simplify_debts.dart';
import '../../screens/settings/providers/settings_providers.dart';
import '../../screens/expenses/utils/split_helpers.dart';
import '../../screens/expenses/utils/split_persistence.dart';
import '../../services/storage/hive_service.dart' show kLocalPrefsBox;
import '../../services/supabase/supabase_service.dart';
import '../storage/storage_providers.dart';

/// Where the guest page lives. The domain is fixed by the Pages deployment.
const kSharePageBase = 'https://lekhamoney.app/s/#';

/// An accepted expense has to be filed under something, and the guest was never
/// asked. Same fallback `Payable.fromJson` uses; the owner can recategorise it
/// like any other expense.
const _shareCategory = 'Miscellaneous';

/// Someone who forgot their PIN and is waiting on the person who shared the
/// link — which is always the owner of these rows, never an administrator.
class PinResetRequest {
  final String personId;
  final String name;
  final DateTime requestedAt;

  const PinResetRequest({
    required this.personId,
    required this.name,
    required this.requestedAt,
  });
}

/// Whether you have copied or shared this person's link from this device.
///
/// Deliberately local: nothing on the server can know whether you actually
/// sent the message, so this only records that you took the link — which is
/// still the difference between "they have not opened it" and "you never sent
/// it to them".
bool shareLinkSent(String token) =>
    Hive.isBoxOpen(kLocalPrefsBox) &&
    Hive.box(kLocalPrefsBox).get('shareSent:$token') == true;

Future<void> markShareLinkSent(String token) async {
  if (!Hive.isBoxOpen(kLocalPrefsBox)) return;
  await Hive.box(kLocalPrefsBox).put('shareSent:$token', true);
}

/// How far a person has got with the link you made for them.
enum ShareProgress { notSent, sent, opened, joined }

/// Read from what actually happened, not from assumptions.
///
/// [openedAt] and [joinedAt] come from the server — the page stamps
/// `last_seen_at` whenever it loads, and `pin_set_at` when a PIN is chosen.
/// [sent] is the one thing no server can know: it is recorded on this device
/// when you tap Copy or Share, and says nothing about whether the message was
/// actually delivered.
ShareProgress shareProgressFor({
  required bool sent,
  DateTime? openedAt,
  DateTime? joinedAt,
}) {
  if (joinedAt != null) return ShareProgress.joined;
  if (openedAt != null) return ShareProgress.opened;
  return sent ? ShareProgress.sent : ShareProgress.notSent;
}

String shareProgressLabel(ShareProgress progress) => switch (progress) {
  ShareProgress.joined => 'Joined',
  ShareProgress.opened => 'Opened it, no PIN yet',
  ShareProgress.sent => 'Link copied, not opened yet',
  ShareProgress.notSent => 'Not shared yet',
};

/// One person on a group, and the link that is theirs.
class SharedGroupMember {
  final String personId;
  final String name;
  final String token;

  /// Last time their page loaded, or null if it never has.
  final DateTime? openedAt;

  /// When they chose a PIN. Null means they have not joined.
  final DateTime? joinedAt;

  const SharedGroupMember({
    required this.personId,
    required this.name,
    required this.token,
    this.openedAt,
    this.joinedAt,
  });

  String get link => '$kSharePageBase$token';
}

/// A shared space with a name on it. The app keeps no group of its own — a
/// group is a space with more than one participant, and the owner's own books
/// stay the pairwise debts they always were.
class SharedGroup {
  final String id;
  final String title;
  final List<SharedGroupMember> members;

  const SharedGroup({
    required this.id,
    required this.title,
    required this.members,
  });
}

class SharedInbox {
  final List<SharedEntry> pending;
  final List<PinResetRequest> resets;
  final List<SharedGroup> groups;

  const SharedInbox({
    this.pending = const [],
    this.resets = const [],
    this.groups = const [],
  });

  int get count => pending.length + resets.length;

  List<SharedEntry> forSpace(String spaceId) =>
      pending.where((e) => e.spaceId == spaceId).toList();

  List<SharedEntry> forPerson(String person) => pending
      .where((e) => e.personName.toLowerCase() == person.toLowerCase())
      .toList();

  List<PinResetRequest> resetsForPerson(String person) => resets
      .where((r) => r.name.toLowerCase() == person.toLowerCase())
      .toList();
}

/// Everything the owner's app does with shared pages.
///
/// All of it is plain PostgREST under the owner-scoped RLS policies — the Edge
/// Function is the guest's door only, and adding an owner action to it would
/// mean building a second permission model beside the one Postgres already
/// enforces.
class SharedLedgerNotifier extends StateNotifier<SharedInbox> {
  final Ref _ref;

  SharedLedgerNotifier(this._ref) : super(const SharedInbox());

  /// Backend work is skipped outright when signed out. `currentUserIdProvider`
  /// falls back to a local placeholder id that is not a real `auth.users` row,
  /// so using it here would fail every policy.
  String? get _userId => SupabaseService.client.auth.currentUser?.id;

  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;
    final client = SupabaseService.client;
    try {
      final rows =
          await client
                  .from('shared_entries')
                  .select(
                    'id, space_id, kind, total, payer_name, shares, note, '
                    'occurred_on, author_person_id',
                  )
                  .eq('status', 'pending')
                  .order('created_at')
              as List<dynamic>;

      final people = await _peopleByIdFor(rows);

      // Empty means we cannot tell who "the owner" is on an entry, so nothing
      // is filtered — better an extra card than a hidden one.
      final ownerName = _ref.read(settingsProvider).displayName.trim();

      final pending = <SharedEntry>[];
      for (final row in rows.cast<Map<String, dynamic>>()) {
        final name = people[row['author_person_id']?.toString()];
        // An entry whose author was deleted has nobody to owe; drop it rather
        // than render a card naming an empty string.
        if (name == null || name.isEmpty) continue;
        final entry = SharedEntry.fromRow(row, personName: name);
        if (ownerName.isNotEmpty &&
            !entryInvolvesOwner(entry, ownerName: ownerName)) {
          continue;
        }
        pending.add(entry);
      }

      // Everything for this owner in one go, filtered here rather than with a
      // server-side `not.is.null`: there are only ever a handful of rows, and
      // this leaves no room for the filter syntax to be subtly wrong.
      final peopleRows =
          await client
                  .from('shared_people')
                  .select('id, name, pin_reset_requested_at, pin_set_at')
                  .eq('owner_id', userId)
              as List<dynamic>;
      final participantRows =
          await client
                  .from('shared_participants')
                  .select('person_id, space_id, token, last_seen_at')
                  .eq('owner_id', userId)
                  .isFilter('revoked_at', null)
              as List<dynamic>;

      final resets = <PinResetRequest>[];
      for (final r in peopleRows.cast<Map<String, dynamic>>()) {
        final at = DateTime.tryParse(
          r['pin_reset_requested_at']?.toString() ?? '',
        );
        if (at == null) continue;
        resets.add(
          PinResetRequest(
            personId: r['id'].toString(),
            name: r['name'] as String? ?? '',
            requestedAt: at,
          ),
        );
      }

      // A space with a title is a group; one without is a pairwise share.
      final spaceRows =
          await client
                  .from('shared_spaces')
                  .select('id, title')
                  .eq('owner_id', userId)
                  .isFilter('archived_at', null)
              as List<dynamic>;

      final nameById = {
        for (final r in peopleRows.cast<Map<String, dynamic>>())
          r['id'].toString(): r['name'] as String? ?? '',
      };
      final joinedById = {
        for (final r in peopleRows.cast<Map<String, dynamic>>())
          r['id'].toString(): DateTime.tryParse(
            r['pin_set_at']?.toString() ?? '',
          ),
      };

      final groups = <SharedGroup>[];
      for (final sp in spaceRows.cast<Map<String, dynamic>>()) {
        final title = (sp['title'] as String?)?.trim() ?? '';
        if (title.isEmpty) continue;
        final id = sp['id'].toString();
        final members = <SharedGroupMember>[];
        for (final part in participantRows.cast<Map<String, dynamic>>()) {
          if (part['space_id'].toString() != id) continue;
          final personId = part['person_id'].toString();
          members.add(
            SharedGroupMember(
              personId: personId,
              name: nameById[personId] ?? '',
              token: part['token'].toString(),
              openedAt: DateTime.tryParse(
                part['last_seen_at']?.toString() ?? '',
              ),
              joinedAt: joinedById[personId],
            ),
          );
        }
        groups.add(SharedGroup(id: id, title: title, members: members));
      }

      state = SharedInbox(pending: pending, resets: resets, groups: groups);

      // Push the owner's own ledger out while we are here. Without it the guest
      // sees a balance with nothing behind it, which is the opposite of the
      // point of sharing it at all.
      for (final part in participantRows.cast<Map<String, dynamic>>()) {
        final personId = part['person_id'].toString();
        final name = nameById[personId];
        if (name == null || name.isEmpty) continue;
        final spaceId = part['space_id'].toString();
        // Groups are summed from their own entries by the function — there is
        // no pairwise history to project into them, and pushing one person's
        // unrelated debts into a group would be wrong as well as confusing.
        if (groups.any((g) => g.id == spaceId)) continue;
        await _syncSpace(name, personId: personId, spaceId: spaceId);
      }
    } catch (e) {
      // Same posture as every other network path here: fail quiet, try again
      // on the next tick rather than putting an error in front of the user.
      debugPrint('shared ledger refresh failed: $e');
    }
  }

  Future<Map<String, String>> _peopleByIdFor(List<dynamic> rows) async {
    final ids = rows
        .cast<Map<String, dynamic>>()
        .map((r) => r['author_person_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return const {};
    final people =
        await SupabaseService.client
                .from('shared_people')
                .select('id, name')
                .inFilter('id', ids)
            as List<dynamic>;
    return {
      for (final p in people.cast<Map<String, dynamic>>())
        p['id'].toString(): p['name'] as String? ?? '',
    };
  }

  /// The link for [person], creating the space and identity the first time.
  /// Returns null when signed out or the write fails — the caller says so
  /// rather than handing over a URL that leads nowhere.
  Future<String?> shareLinkFor(
    String person, {
    required String ownerName,
  }) async {
    final userId = _userId;
    if (userId == null) return null;
    final client = SupabaseService.client;
    final name = person.trim();
    final key = name.toLowerCase();

    try {
      final personRow = await client
          .from('shared_people')
          .upsert({
            'owner_id': userId,
            'name': name,
            'name_key': key,
          }, onConflict: 'owner_id,name_key')
          .select('id')
          .single();
      final personId = personRow['id'].toString();

      // ponytail: a person has exactly one space today, because only pairwise
      // shares exist. When groups land this needs to pick the space whose
      // title is null.
      final existing = await client
          .from('shared_participants')
          .select('token')
          .eq('person_id', personId)
          .isFilter('revoked_at', null)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        await _syncSpace(person);
        return '$kSharePageBase${existing['token']}';
      }

      final spaceRow = await client
          .from('shared_spaces')
          .insert({'owner_id': userId, 'owner_name': ownerName})
          .select('id')
          .single();

      final token = _newToken();
      await client.from('shared_participants').insert({
        'token': token,
        'owner_id': userId,
        'space_id': spaceRow['id'],
        'person_id': personId,
        'owner_net': _ref.read(personBalanceProvider(person))?.net ?? 0,
      });
      await _syncSpace(
        person,
        personId: personId,
        spaceId: spaceRow['id'].toString(),
      );
      return '$kSharePageBase$token';
    } catch (e) {
      debugPrint('share link failed: $e');
      return null;
    }
  }

  /// Create a named space with a link for each person.
  ///
  /// Reuses each person's existing identity, so somebody already in a one-to-one
  /// share keeps the PIN they already set rather than being asked for a new one
  /// per group.
  Future<bool> createGroup(
    String title,
    List<String> names, {
    required String ownerName,
  }) async {
    final userId = _userId;
    if (userId == null || names.isEmpty) return false;
    final client = SupabaseService.client;
    try {
      final space = await client
          .from('shared_spaces')
          .insert({
            'owner_id': userId,
            'owner_name': ownerName,
            'title': title.trim(),
          })
          .select('id')
          .single();
      final spaceId = space['id'];

      for (final raw in names) {
        final name = raw.trim();
        if (name.isEmpty) continue;
        final person = await client
            .from('shared_people')
            .upsert({
              'owner_id': userId,
              'name': name,
              'name_key': name.toLowerCase(),
            }, onConflict: 'owner_id,name_key')
            .select('id')
            .single();
        await client.from('shared_participants').insert({
          'token': _newToken(),
          'owner_id': userId,
          'space_id': spaceId,
          'person_id': person['id'],
          // Groups carry no opening balance: they start empty and the maths is
          // derived from what gets added.
          'owner_net': 0,
        });
      }
      await refresh();
      return true;
    } catch (e) {
      debugPrint('create group failed: $e');
      return false;
    }
  }

  /// 64 hex characters, the same generator the SMS ingest token uses.
  String _newToken() =>
      const Uuid().v4().replaceAll('-', '') +
      const Uuid().v4().replaceAll('-', '');

  /// Re-uploading an identical projection every minute is pure waste; this is
  /// the cheapest possible guard against it.
  final Map<String, String> _lastPushed = {};

  /// Push the balance **and the items behind it** to [person]'s shared page.
  ///
  /// The balance on its own was not enough: the guest saw a number with nothing
  /// explaining it. These rows are a projection — the app stays the only place
  /// they are authored, and the page never edits them.
  ///
  /// It is also why the app and the page cannot disagree. There is one balance,
  /// computed from `peopleBalancesProvider`, and the Edge Function only ever
  /// echoes what is written here.
  Future<void> _syncSpace(
    String person, {
    String? personId,
    String? spaceId,
  }) async {
    final userId = _userId;
    if (userId == null) return;
    final client = SupabaseService.client;
    try {
      var pid = personId;
      var sid = spaceId;
      if (pid == null) {
        final row = await client
            .from('shared_people')
            .select('id')
            .eq('owner_id', userId)
            .eq('name_key', person.trim().toLowerCase())
            .maybeSingle();
        if (row == null) return;
        pid = row['id'].toString();
      }
      if (sid == null) {
        final row = await client
            .from('shared_participants')
            .select('space_id')
            .eq('person_id', pid)
            .isFilter('revoked_at', null)
            .limit(1)
            .maybeSingle();
        if (row == null) return;
        sid = row['space_id'].toString();
      }

      final ownerName = _ref.read(settingsProvider).displayName.trim();
      if (ownerName.isEmpty) return;

      // Debts an accepted entry created are already on the page as the guest's
      // own submission. Projecting them as well would show every shared bill
      // twice, once from each side.
      final acceptedRows =
          await client
                  .from('shared_entries')
                  .select('linked_expense_id')
                  .eq('space_id', sid)
              as List<dynamic>;
      final fromShare = <String>{
        for (final r in acceptedRows.cast<Map<String, dynamic>>())
          if (r['linked_expense_id'] != null) r['linked_expense_id'].toString(),
      };

      final balance = _ref.read(personBalanceProvider(person));
      final net = balance?.net ?? 0;
      final rows = <Map<String, dynamic>>[];
      for (final item in balance?.items ?? const <PersonLedgerItem>[]) {
        if (item.settled) continue;
        final source =
            item.receivable?.sourceExpenseId ?? item.payable?.sourceExpenseId;
        if (source != null && fromShare.contains(source)) continue;
        rows.add({
          'id': item.id,
          'owner_id': userId,
          'space_id': sid,
          // No author: this came from the app, not from anyone on the page.
          'author_person_id': null,
          'kind': 'expense',
          'total': item.amount,
          'payer_name': item.isReceivable ? ownerName : person,
          'shares': item.isReceivable
              ? {person: item.amount}
              : {ownerName: item.amount},
          'note': item.note,
          'occurred_on': item.date.toIso8601String().substring(0, 10),
          'status': 'accepted',
        });
      }

      final ids = rows.map((r) => r['id'].toString()).join(',');
      final fingerprint =
          '$net|${rows.map((r) => '${r['id']}:${r['total']}').join(',')}';
      if (_lastPushed[pid] == fingerprint) return;
      _lastPushed[pid] = fingerprint;

      await client
          .from('shared_participants')
          .update({'owner_net': net})
          .eq('person_id', pid);

      if (rows.isNotEmpty) {
        await client.from('shared_entries').upsert(rows);
      }
      // Drop projected rows for debts that no longer exist locally — an upsert
      // on its own would leave a deleted debt on the page forever.
      var stale = client
          .from('shared_entries')
          .delete()
          .eq('space_id', sid)
          .isFilter('author_person_id', null);
      if (rows.isNotEmpty) {
        stale = stale.not('id', 'in', '($ids)');
      }
      await stale;
    } catch (e) {
      debugPrint('space sync failed: $e');
    }
  }

  Future<void> decide(
    SharedEntry entry,
    String status, {
    String? linkedExpenseId,
  }) async {
    try {
      await SupabaseService.client
          .from('shared_entries')
          .update({
            'status': status,
            'decided_at': DateTime.now().toUtc().toIso8601String(),
            'linked_expense_id': ?linkedExpenseId,
          })
          .eq('id', entry.id);
    } catch (e) {
      // Rethrow rather than drop it from the list anyway. The row is still
      // pending in Postgres, so hiding the card only means it reappears on the
      // next refresh — after the user has been told it was dealt with.
      debugPrint('decide failed: $e');
      rethrow;
    }
    state = SharedInbox(
      pending: state.pending.where((e) => e.id != entry.id).toList(),
      resets: state.resets,
      groups: state.groups,
    );
    await _syncSpace(entry.personName);
  }

  /// Clear the PIN so the guest can set a new one, and bump `pin_version` so
  /// any device still holding a week-old session is signed out at the same
  /// moment.
  /// Returns false when the reset did not go through, so the caller does not
  /// promise the guest can set a new PIN when their old one still works.
  Future<bool> allowReset(
    PinResetRequest request, {
    required int bumpTo,
  }) async {
    try {
      await SupabaseService.client
          .from('shared_people')
          .update({
            'pin_hash': null,
            'pin_salt': null,
            'pin_set_at': null,
            'pin_version': bumpTo,
            'failed_count': 0,
            'locked_until': null,
            'pin_reset_requested_at': null,
          })
          .eq('id', request.personId);
    } catch (e) {
      debugPrint('reset failed: $e');
      return false;
    }
    state = SharedInbox(
      pending: state.pending,
      resets: state.resets
          .where((r) => r.personId != request.personId)
          .toList(),
      groups: state.groups,
    );
    return true;
  }

  /// The current `pin_version`, so a reset can raise it by exactly one without
  /// a database-side expression.
  Future<int> pinVersionOf(PinResetRequest request) async {
    try {
      final row = await SupabaseService.client
          .from('shared_people')
          .select('pin_version')
          .eq('id', request.personId)
          .maybeSingle();
      return (row?['pin_version'] as int?) ?? 1;
    } catch (_) {
      return 1;
    }
  }

  Future<void> dismissReset(PinResetRequest request) async {
    try {
      await SupabaseService.client
          .from('shared_people')
          .update({'pin_reset_requested_at': null})
          .eq('id', request.personId);
    } catch (e) {
      debugPrint('dismiss reset failed: $e');
    }
    state = SharedInbox(
      pending: state.pending,
      resets: state.resets
          .where((r) => r.personId != request.personId)
          .toList(),
      groups: state.groups,
    );
  }
}

final sharedInboxProvider =
    StateNotifierProvider<SharedLedgerNotifier, SharedInbox>(
      (ref) => SharedLedgerNotifier(ref),
    );

/// Accept a guest's entry into the ledger.
///
/// Takes a [WidgetRef] rather than living on the notifier so it can call
/// `createSplitDebts` — the same function the add-expense form uses. That is
/// the point: an accepted entry is stored by the identical code path as one
/// typed by hand, so budgets, warnings, sync and insights all behave normally
/// and there is no second way for money to enter the app.
Future<void> acceptSharedEntry({
  required WidgetRef ref,
  required SharedEntry entry,
  required String userId,
  required String ownerName,
}) async {
  final inbox = ref.read(sharedInboxProvider.notifier);

  if (entry.isSettlement) {
    if (settlementPaysOwner(entry, ownerName: ownerName)) {
      await ref
          .read(receivablesProvider.notifier)
          .settlePersonReceivables(
            entry.personName,
            entry.total,
            note: entry.note,
          );
    } else {
      await ref
          .read(payablesProvider.notifier)
          .settlePersonPayables(
            entry.personName,
            entry.total,
            note: entry.note,
          );
    }
    await inbox.decide(entry, 'accepted');
    return;
  }

  final config = splitConfigFor(entry, ownerName: ownerName);
  final split = computeSplit(
    total: entry.total,
    people: config.people,
    mode: config.mode,
    exactAmounts: config.exact,
  );

  String? expenseId;
  // A bill the guest covered entirely is not the owner's spending, so it gets
  // no expense row — only the debt, if there is one.
  if (split.myShare > 0) {
    final expense = Expense(
      id: const Uuid().v4(),
      userId: userId,
      amount: split.myShare,
      category: _shareCategory,
      description: entry.note ?? 'Shared with ${entry.personName}',
      date: entry.occurredOn,
      paymentMethod: null,
      createdAt: DateTime.now(),
      updatedAt: null,
    );
    await ref.read(expensesProvider.notifier).addExpense(expense);
    expenseId = expense.id;
  }

  await createSplitDebts(
    ref: ref,
    userId: userId,
    // Falls back to the entry's own id so the debts are still tagged with
    // something stable when there was no expense to hang them off.
    sourceExpenseId: expenseId ?? entry.id,
    config: config,
    split: split,
    note: entry.note,
    date: entry.occurredOn,
    category: _shareCategory,
  );

  // Always a value, even when no expense was written: this is the id
  // createSplitDebts tagged the debts with, and the projection reads it to know
  // they are already on the page as the guest's own entry.
  await inbox.decide(entry, 'accepted', linkedExpenseId: expenseId ?? entry.id);
}

/// A group as everyone on its page sees it: where each person stands, and the
/// fewest payments that would clear the whole thing.
///
/// The owner has no share link and should not need one — they own the group.
/// But that left them with nowhere at all to see its maths, since the group
/// sheet only ever showed the links and whatever was waiting on them. This is
/// that missing view, and it is what `simplifyDebts` was written for.
class GroupLedger {
  /// Owner first, then everyone else.
  final List<String> members;

  /// Positive means that person is owed.
  final Map<String, double> balances;
  final List<Transfer> transfers;
  final List<SharedEntry> entries;

  const GroupLedger({
    required this.members,
    required this.balances,
    required this.transfers,
    required this.entries,
  });

  double netFor(String name) => balances[name] ?? 0;
}

/// Fetched on demand rather than on the 60s tick: it is only ever looked at
/// while the group sheet is open.
final groupLedgerProvider = FutureProvider.family<GroupLedger?, String>((
  ref,
  spaceId,
) async {
  final inbox = ref.watch(sharedInboxProvider);
  final group = inbox.groups.where((g) => g.id == spaceId).firstOrNull;
  if (group == null) return null;
  final ownerName = ref.read(settingsProvider).displayName.trim();
  if (ownerName.isEmpty) return null;

  final client = SupabaseService.client;
  if (client.auth.currentUser == null) return null;

  final rows =
      await client
              .from('shared_entries')
              .select(
                'id, space_id, kind, total, payer_name, shares, note, '
                'occurred_on, author_person_id',
              )
              .eq('space_id', spaceId)
              .neq('status', 'dismissed')
              .order('occurred_on', ascending: false)
          as List<dynamic>;

  final nameById = {for (final m in group.members) m.personId: m.name};
  final entries = <SharedEntry>[];
  for (final row in rows.cast<Map<String, dynamic>>()) {
    entries.add(
      SharedEntry.fromRow(
        row,
        // The author. An entry the owner added themselves has no participant
        // row behind it, so it falls back to whoever paid.
        personName:
            nameById[row['author_person_id']?.toString()] ??
            (row['payer_name'] as String? ?? ownerName),
      ),
    );
  }

  // Same arithmetic the Edge Function does for the guests, so the app and the
  // page cannot show different numbers: whoever paid is up by the whole bill,
  // and everyone is down by their share.
  final members = [ownerName, ...group.members.map((m) => m.name)];
  final balances = <String, double>{for (final name in members) name: 0};
  for (final entry in entries) {
    balances[entry.payerName] = (balances[entry.payerName] ?? 0) + entry.total;
    for (final share in entry.shares.entries) {
      balances[share.key] = (balances[share.key] ?? 0) - share.value;
    }
  }
  for (final name in balances.keys.toList()) {
    balances[name] = (balances[name]! * 100).round() / 100;
  }

  return GroupLedger(
    members: members,
    balances: balances,
    transfers: simplifyDebts(balances),
    entries: entries,
  );
});
