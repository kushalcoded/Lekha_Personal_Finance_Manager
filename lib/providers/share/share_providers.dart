import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/expense/expense_model.dart';
import '../../models/share/shared_entry.dart';
import '../../screens/debts/providers/people_balance_providers.dart';
import '../../screens/settings/providers/settings_providers.dart';
import '../../screens/expenses/utils/split_helpers.dart';
import '../../screens/expenses/utils/split_persistence.dart';
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

class SharedInbox {
  final List<SharedEntry> pending;
  final List<PinResetRequest> resets;

  const SharedInbox({this.pending = const [], this.resets = const []});

  int get count => pending.length + resets.length;

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

      final pending = <SharedEntry>[];
      for (final row in rows.cast<Map<String, dynamic>>()) {
        final name = people[row['author_person_id']?.toString()];
        // An entry whose author was deleted has nobody to owe; drop it rather
        // than render a card naming an empty string.
        if (name == null || name.isEmpty) continue;
        pending.add(SharedEntry.fromRow(row, personName: name));
      }

      // Everything for this owner in one go, filtered here rather than with a
      // server-side `not.is.null`: there are only ever a handful of rows, and
      // this leaves no room for the filter syntax to be subtly wrong.
      final peopleRows =
          await client
                  .from('shared_people')
                  .select('id, name, pin_reset_requested_at')
                  .eq('owner_id', userId)
              as List<dynamic>;
      final participantRows =
          await client
                  .from('shared_participants')
                  .select('person_id, space_id')
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

      state = SharedInbox(pending: pending, resets: resets);

      // Push the owner's own ledger out while we are here. Without it the guest
      // sees a balance with nothing behind it, which is the opposite of the
      // point of sharing it at all.
      final nameById = {
        for (final r in peopleRows.cast<Map<String, dynamic>>())
          r['id'].toString(): r['name'] as String? ?? '',
      };
      for (final part in participantRows.cast<Map<String, dynamic>>()) {
        final personId = part['person_id'].toString();
        final name = nameById[personId];
        if (name == null || name.isEmpty) continue;
        await _syncSpace(
          name,
          personId: personId,
          spaceId: part['space_id'].toString(),
        );
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
  Future<String?> shareLinkFor(String person, {required String ownerName}) async {
    final userId = _userId;
    if (userId == null) return null;
    final client = SupabaseService.client;
    final name = person.trim();
    final key = name.toLowerCase();

    try {
      final personRow =
          await client
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
      final existing =
          await client
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

      final spaceRow =
          await client
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
      debugPrint('decide failed: $e');
    }
    state = SharedInbox(
      pending: state.pending.where((e) => e.id != entry.id).toList(),
      resets: state.resets,
    );
    await _syncSpace(entry.personName);
  }

  /// Clear the PIN so the guest can set a new one, and bump `pin_version` so
  /// any device still holding a week-old session is signed out at the same
  /// moment.
  Future<void> allowReset(PinResetRequest request, {required int bumpTo}) async {
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
      return;
    }
    state = SharedInbox(
      pending: state.pending,
      resets: state.resets
          .where((r) => r.personId != request.personId)
          .toList(),
    );
  }

  /// The current `pin_version`, so a reset can raise it by exactly one without
  /// a database-side expression.
  Future<int> pinVersionOf(PinResetRequest request) async {
    try {
      final row =
          await SupabaseService.client
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
          .settlePersonPayables(entry.personName, entry.total, note: entry.note);
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
