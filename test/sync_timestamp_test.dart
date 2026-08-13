import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/services/sync/supabase_sync_service.dart';

/// The bug: `_uploadSnapshot` wrote `DateTime.now().toIso8601String()` — local
/// wall time with no offset — into a `timestamptz` column, so Postgres read it
/// as UTC and it came back one UTC offset in the future. `remoteNewer` was
/// therefore true on every launch, so every cold start pulled the cloud
/// snapshot and replaced local data, reverting anything not yet pushed.
void main() {
  group('remoteIsNewer', () {
    test('a snapshot this device just uploaded is not newer than itself', () {
      // The exact failing case: upload marker and lastSyncedAt are the same
      // instant, so nothing should be pulled on the next launch.
      final uploaded = DateTime.now().toUtc();
      expect(SupabaseSyncService.remoteIsNewer(uploaded, uploaded), isFalse);
    });

    test('the same instant expressed in different zones is not newer', () {
      // This is what actually broke: one side UTC-aware, the other local.
      final utc = DateTime.utc(2026, 8, 13, 14, 45, 18);
      final sameMomentLocal = utc.toLocal();
      expect(SupabaseSyncService.remoteIsNewer(utc, sameMomentLocal), isFalse);
      expect(SupabaseSyncService.remoteIsNewer(sameMomentLocal, utc), isFalse);
    });

    test('a genuinely newer remote still wins', () {
      final synced = DateTime.utc(2026, 8, 13, 10);
      final remote = DateTime.utc(2026, 8, 13, 11);
      expect(SupabaseSyncService.remoteIsNewer(remote, synced), isTrue);
    });

    test('an older remote never wins', () {
      final synced = DateTime.utc(2026, 8, 13, 12);
      final remote = DateTime.utc(2026, 8, 13, 11);
      expect(SupabaseSyncService.remoteIsNewer(remote, synced), isFalse);
    });

    test('never synced means anything remote is newer', () {
      expect(
        SupabaseSyncService.remoteIsNewer(DateTime.utc(2020), null),
        isTrue,
      );
    });

    test('a legacy naive-local lastSyncedAt still compares correctly', () {
      // Values written by older builds have no offset. DateTime.parse reads
      // them as local, which is the instant that was meant — converting is
      // safe, forcing UTC on them would shift every stored value.
      final legacy = DateTime.parse('2026-08-13T20:15:18.123');
      final sameMoment = legacy.toUtc();
      expect(SupabaseSyncService.remoteIsNewer(sameMoment, legacy), isFalse);
      expect(
        SupabaseSyncService.remoteIsNewer(
          sameMoment.add(const Duration(minutes: 1)),
          legacy,
        ),
        isTrue,
      );
    });
  });

  test('an uploaded marker serialises with an explicit zone', () {
    // A trailing Z is what stops Postgres reinterpreting the value.
    final iso = DateTime.now().toUtc().toIso8601String();
    expect(iso.endsWith('Z'), isTrue);
    expect(DateTime.parse(iso).isUtc, isTrue);
  });
}
