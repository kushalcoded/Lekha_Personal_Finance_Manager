import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/services/sync/supabase_sync_service.dart';

/// Two separate data-loss bugs live behind these tests.
///
/// The first: `_uploadSnapshot` wrote local wall time with no offset into a
/// `timestamptz` column, so the remote always looked newer and every cold
/// start pulled over local data.
///
/// The second: leaving the app uploaded unconditionally. A phone that had not
/// been touched in a day uploaded its stale copy on the way to the background,
/// and the web app's next sync pulled it over the expenses just added there.
void main() {
  group('remoteChanged', () {
    test('the stamp this device last saw is not a change', () {
      final stamp = DateTime.utc(2026, 9, 14, 10, 0, 0, 123, 456);
      expect(SupabaseSyncService.remoteChanged(stamp, stamp), isFalse);
    });

    test('the same instant expressed in different zones is not a change', () {
      final utc = DateTime.utc(2026, 8, 13, 14, 45, 18);
      final sameMomentLocal = utc.toLocal();
      expect(SupabaseSyncService.remoteChanged(utc, sameMomentLocal), isFalse);
      expect(SupabaseSyncService.remoteChanged(sameMomentLocal, utc), isFalse);
    });

    test('a later write by another device is a change', () {
      final seen = DateTime.utc(2026, 8, 13, 10);
      expect(
        SupabaseSyncService.remoteChanged(DateTime.utc(2026, 8, 13, 11), seen),
        isTrue,
      );
    });

    test('an EARLIER stamp is a change too', () {
      // Another device with a slow clock wrote after us. Under "is it newer?"
      // this read as nothing to do, and that device's data was never pulled.
      final seen = DateTime.utc(2026, 8, 13, 12);
      expect(
        SupabaseSyncService.remoteChanged(DateTime.utc(2026, 8, 13, 11), seen),
        isTrue,
      );
    });

    test('never synced means whatever is there is new to us', () {
      expect(
        SupabaseSyncService.remoteChanged(DateTime.utc(2020), null),
        isTrue,
      );
    });

    test('a legacy naive-local stamp still matches its own instant', () {
      // Values written by older builds have no offset and parse as local,
      // which is the instant that was meant. `==` would call these different
      // because it also compares the UTC flag.
      final legacy = DateTime.parse('2026-08-13T20:15:18.123');
      final sameMoment = legacy.toUtc();
      expect(SupabaseSyncService.remoteChanged(sameMoment, legacy), isFalse);
      expect(
        SupabaseSyncService.remoteChanged(
          sameMoment.add(const Duration(minutes: 1)),
          legacy,
        ),
        isTrue,
      );
    });
  });

  test('an uploaded stamp serialises with an explicit zone', () {
    // A trailing Z is what stops Postgres reinterpreting the value.
    final iso = DateTime.now().toUtc().toIso8601String();
    expect(iso.endsWith('Z'), isTrue);
    expect(DateTime.parse(iso).isUtc, isTrue);
  });

  group('decide', () {
    SyncAction decide({
      bool pushOnly = false,
      bool hasRemote = true,
      bool remoteChanged = false,
      bool localEmpty = false,
      bool localDirty = false,
    }) => SupabaseSyncService.decide(
      pushOnly: pushOnly,
      hasRemote: hasRemote,
      remoteChanged: remoteChanged,
      localEmpty: localEmpty,
      localDirty: localDirty,
    );

    test('a device with no edits never uploads over the cloud', () {
      // The reported loss: the stale phone going to the background.
      expect(decide(pushOnly: true), SyncAction.nothing);
      expect(decide(pushOnly: true, remoteChanged: true), SyncAction.nothing);
      expect(decide(), SyncAction.nothing);
    });

    test('a device with no edits takes what another device wrote', () {
      expect(decide(remoteChanged: true), SyncAction.pull);
    });

    test('edits go up when nobody else has written', () {
      expect(decide(localDirty: true), SyncAction.upload);
      expect(decide(localDirty: true, pushOnly: true), SyncAction.upload);
    });

    test('edits on both sides merge rather than one side winning', () {
      expect(decide(localDirty: true, remoteChanged: true), SyncAction.merge);
      expect(
        decide(localDirty: true, remoteChanged: true, pushOnly: true),
        SyncAction.merge,
      );
    });

    test('a device that just deleted its last record never pulls', () {
      // Deleting the only expense was undone by the next sync: an empty device
      // looked factory-fresh and pulled the cloud copy back over the delete.
      expect(decide(localEmpty: true, localDirty: true), SyncAction.upload);
      expect(
        decide(localEmpty: true, localDirty: true, remoteChanged: true),
        SyncAction.merge,
      );
    });

    test('a genuinely fresh device still adopts the cloud', () {
      expect(decide(localEmpty: true), SyncAction.pull);
      expect(decide(localEmpty: true, remoteChanged: true), SyncAction.pull);
    });

    test('with nothing in the cloud yet, whatever is here goes up', () {
      expect(decide(hasRemote: false), SyncAction.upload);
      expect(decide(hasRemote: false, pushOnly: true), SyncAction.upload);
    });
  });

  group('refuseEmptyPush', () {
    test('an accidentally empty device cannot flatten the cloud', () {
      expect(
        SupabaseSyncService.refuseEmptyPush(
          localEmpty: true,
          remoteHasData: true,
          localDirty: false,
        ),
        isTrue,
      );
    });

    test('a deliberate deletion is allowed through', () {
      // Only writes that went through the app set the mutation marker;
      // clearAllData and a mid-restore blank do not.
      expect(
        SupabaseSyncService.refuseEmptyPush(
          localEmpty: true,
          remoteHasData: true,
          localDirty: true,
        ),
        isFalse,
      );
    });

    test('nothing to protect when the cloud is empty too', () {
      expect(
        SupabaseSyncService.refuseEmptyPush(
          localEmpty: true,
          remoteHasData: false,
          localDirty: false,
        ),
        isFalse,
      );
    });
  });
}
