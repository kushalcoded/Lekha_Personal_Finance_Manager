import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/expense/expense_model.dart';
import '../../models/share/shared_entry.dart';
import '../../screens/debts/providers/people_balance_providers.dart';
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

      final resetRows =
          await client
                  .from('shared_people')
                  .select('id, name, pin_reset_requested_at')
                  .not('pin_reset_requested_at', 'is', null)
              as List<dynamic>;

      state = SharedInbox(
        pending: pending,
        resets: resetRows.cast<Map<String, dynamic>>().map((r) {
          return PinResetRequest(
            personId: r['id'].toString(),
            name: r['name'] as String? ?? '',
            requestedAt:
                DateTime.tryParse(
                  r['pin_reset_requested_at']?.toString() ?? '',
                ) ??
                DateTime.now(),
          );
        }).toList(),
      );
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
        await _pushNet(person);
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
        'owner_net': _netFor(person),
      });
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

  double _netFor(String person) =>
      _ref.read(personBalanceProvider(person))?.net ?? 0;

  /// Push the app's own balance out to every link with [person].
  ///
  /// This is the whole reason the guest page and the app can never disagree:
  /// there is one balance, computed here from `peopleBalancesProvider`, and the
  /// function only ever echoes it back.
  Future<void> _pushNet(String person) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final client = SupabaseService.client;
      final people =
          await client
                  .from('shared_people')
                  .select('id')
                  .eq('owner_id', userId)
                  .eq('name_key', person.trim().toLowerCase())
                  .maybeSingle();
      if (people == null) return;
      await client
          .from('shared_participants')
          .update({'owner_net': _netFor(person)})
          .eq('person_id', people['id']);
    } catch (e) {
      debugPrint('net push failed: $e');
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
    await _pushNet(entry.personName);
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

  await inbox.decide(entry, 'accepted', linkedExpenseId: expenseId);
}
