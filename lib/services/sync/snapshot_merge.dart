/// Record-level merge of two whole-account snapshots.
///
/// Used when this device has edits the cloud has not seen AND another device
/// has written since we last synced. Before this existed one side's snapshot
/// simply replaced the other's, which is how expenses added on the web app
/// disappeared under a phone's older copy.
///
/// Pure on purpose: maps in, map out, no Hive, so every rule is testable.
library;

import 'dart:convert';

/// Snapshot list key → the clock-key prefix its records use.
const kMergedCollections = {
  'expenses': 'expense',
  'receivables': 'receivable',
  'payables': 'payable',
  'recurringTemplates': 'recurringTemplate',
};

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// When a record (or settings key) last changed, and whether that change was
/// deleting it. Records that predate clocks have none and count as the epoch,
/// so any real change on the other side beats them.
class ChangeClock {
  final DateTime at;
  final bool deleted;

  const ChangeClock(this.at, {this.deleted = false});

  static ChangeClock? parse(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['at']}');
    if (at == null) return null;
    return ChangeClock(at.toUtc(), deleted: raw['deleted'] == true);
  }

  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'deleted': deleted,
  };
}

Map<String, dynamic> mergeSnapshots(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) {
  final localClocks = _clocks(local['recordClock']);
  final remoteClocks = _clocks(remote['recordClock']);
  final merged = Map<String, dynamic>.from(local);

  for (final entry in kMergedCollections.entries) {
    merged[entry.key] = _mergeRecords(
      local: _byId(local[entry.key]),
      remote: _byId(remote[entry.key]),
      localClocks: localClocks,
      remoteClocks: remoteClocks,
      prefix: entry.value,
      withSettlements: entry.key == 'receivables' || entry.key == 'payables',
    );
  }

  merged['recordClock'] = {
    for (final key in {...localClocks.keys, ...remoteClocks.keys})
      key: _later(localClocks[key], remoteClocks[key])!.toJson(),
  };

  final settingsMerge = _mergeSettings(
    local: _map(local['settings']),
    remote: _map(remote['settings']),
    localClocks: _stamps(local['settingsClock']),
    remoteClocks: _stamps(remote['settingsClock']),
  );
  merged['settings'] = settingsMerge.values;
  merged['settingsClock'] = settingsMerge.clocks;

  // ponytail: no per-month clocks, so a budget changed on both devices keeps
  // this device's figure. Months only one side has are kept either way.
  merged['monthlyBudgets'] = {
    ..._map(remote['monthlyBudgets']),
    ..._map(local['monthlyBudgets']),
  };

  // Detections are never deleted, only status-changed, and this device has
  // already folded the cloud's statuses in (mergeRemotePending) before the
  // local snapshot was taken. So a union by id loses nothing.
  final localPending = _byId(local['pendingTransactions']);
  merged['pendingTransactions'] = [
    ..._byId(
      remote['pendingTransactions'],
    ).values.where((row) => !localPending.containsKey('${row['id']}')),
    ...localPending.values,
  ];
  merged['smsSeen'] = {..._map(remote['smsSeen']), ..._map(local['smsSeen'])};
  merged['onboardingCompleted'] =
      local['onboardingCompleted'] == true ||
      remote['onboardingCompleted'] == true;
  return merged;
}

List<Map<String, dynamic>> _mergeRecords({
  required Map<String, Map<String, dynamic>> local,
  required Map<String, Map<String, dynamic>> remote,
  required Map<String, ChangeClock> localClocks,
  required Map<String, ChangeClock> remoteClocks,
  required String prefix,
  required bool withSettlements,
}) {
  final out = <Map<String, dynamic>>[];
  for (final id in {...local.keys, ...remote.keys}) {
    final key = '$prefix:$id';
    final l = local[id];
    final r = remote[id];
    final lAt = localClocks[key]?.at ?? _epoch;
    final rAt = remoteClocks[key]?.at ?? _epoch;

    if (l != null && r != null) {
      // Tie goes to this device: it is the one with unsynced edits.
      final winner = rAt.isAfter(lAt) ? r : l;
      final loser = identical(winner, l) ? r : l;
      out.add(withSettlements ? _unionSettlements(winner, loser) : winner);
    } else if (l != null) {
      // Only here. Either the other device deleted it, or never had it.
      final gone = remoteClocks[key];
      if (gone == null || !gone.deleted || lAt.isAfter(gone.at)) out.add(l);
    } else if (r != null) {
      final gone = localClocks[key];
      if (gone == null || !gone.deleted || rAt.isAfter(gone.at)) out.add(r);
    }
  }
  return out;
}

/// Two partial payments recorded on two devices are both real. Whichever copy
/// wins on everything else, its settlements are the union of both sides, and
/// what remains is worked out again from that union.
Map<String, dynamic> _unionSettlements(
  Map<String, dynamic> winner,
  Map<String, dynamic> loser,
) {
  final mine = _byId(winner['settlements']);
  final extra = _byId(
    loser['settlements'],
  ).entries.where((e) => !mine.containsKey(e.key)).map((e) => e.value);
  if (extra.isEmpty) return winner;

  final all = [...mine.values, ...extra]
    ..sort((a, b) => '${a['settledAt']}'.compareTo('${b['settledAt']}'));
  final amount = (winner['amount'] as num?)?.toDouble() ?? 0;
  final paid = all.fold<double>(
    0,
    (sum, s) => sum + ((s['amount'] as num?)?.toDouble() ?? 0),
  );
  final remaining = (amount - paid).clamp(0.0, amount);
  final settled = remaining <= 0.01;

  final result = Map<String, dynamic>.from(winner)
    ..['settlements'] = all
    ..['remainingAmount'] = settled ? 0.0 : remaining;
  if (result.containsKey('isPaid')) {
    result['isPaid'] = settled || winner['isPaid'] == true;
  }
  if (result.containsKey('status')) {
    result['status'] = settled ? 'paid' : 'partial';
  }
  return result;
}

({Map<String, dynamic> values, Map<String, String> clocks}) _mergeSettings({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
  required Map<String, DateTime> localClocks,
  required Map<String, DateTime> remoteClocks,
}) {
  final values = <String, dynamic>{};
  final clocks = <String, String>{};
  final keys = {
    ...local.keys,
    ...remote.keys,
    ...localClocks.keys,
    ...remoteClocks.keys,
  };
  for (final key in keys) {
    final lAt = localClocks[key] ?? _epoch;
    final rAt = remoteClocks[key] ?? _epoch;
    // The newer change wins, including a change that removed the key. With no
    // clock to say otherwise, a key only one side has is simply kept — the
    // whole-map overlay this replaces put a stale device's categories and
    // salary cycle back over the ones just changed elsewhere.
    final Map<String, dynamic> source;
    if (rAt.isAfter(lAt)) {
      source = remote;
    } else if (lAt.isAfter(rAt)) {
      source = local;
    } else {
      source = local.containsKey(key) ? local : remote;
    }
    if (source.containsKey(key)) values[key] = source[key];
    final at = rAt.isAfter(lAt) ? rAt : lAt;
    if (at != _epoch) clocks[key] = at.toIso8601String();
  }
  return (values: values, clocks: clocks);
}

/// Which keys of a settings map changed between [before] and [after].
/// Values are compared as JSON, since that is the form they sync in.
Set<String> changedSettingKeys(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  String encode(Object? v) {
    try {
      return jsonEncode(v);
    } catch (_) {
      return '$v';
    }
  }

  return {
    for (final key in {...before.keys, ...after.keys})
      if (before.containsKey(key) != after.containsKey(key) ||
          encode(before[key]) != encode(after[key]))
        key,
  };
}

ChangeClock? _later(ChangeClock? a, ChangeClock? b) {
  if (a == null) return b;
  if (b == null) return a;
  if (a.at.isAtSameMomentAs(b.at)) return a.deleted ? a : b;
  return a.at.isAfter(b.at) ? a : b;
}

Map<String, ChangeClock> _clocks(Object? raw) => {
  if (raw is Map)
    for (final e in raw.entries) '${e.key}': ?ChangeClock.parse(e.value),
};

Map<String, DateTime> _stamps(Object? raw) => {
  if (raw is Map)
    for (final e in raw.entries)
      '${e.key}': ?DateTime.tryParse('${e.value}')?.toUtc(),
};

Map<String, Map<String, dynamic>> _byId(Object? raw) => {
  for (final row in _list(raw)) '${row['id']}': row,
};

List<Map<String, dynamic>> _list(Object? raw) => raw is List
    ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : const [];

Map<String, dynamic> _map(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
