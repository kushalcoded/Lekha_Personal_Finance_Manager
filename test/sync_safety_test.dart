import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/providers/sms/sms_providers.dart';
import 'package:personal_expanse_tracker/services/sync/supabase_sync_service.dart';

void main() {
  group('empty-snapshot guard', () {
    // Rapid sync taps once overlapped: one run cleared the boxes to restore a
    // pull while another snapshotted them mid-clear and uploaded the empty
    // result, wiping every device. This is the check that refuses that upload.
    test('a snapshot with no money records reads as empty', () {
      expect(
        SupabaseSyncService.snapshotIsEmpty({
          'expenses': <dynamic>[],
          'receivables': <dynamic>[],
          'payables': <dynamic>[],
          'recurringTemplates': <dynamic>[],
          // Settings surviving is exactly the half-restored shape that made
          // the bad upload look legitimate.
          'settings': {'displayName': 'Kushal'},
        }),
        isTrue,
      );
    });

    test('a missing key counts as empty, not as a crash', () {
      expect(SupabaseSyncService.snapshotIsEmpty(<String, dynamic>{}), isTrue);
    });

    test('one expense is enough to protect the snapshot', () {
      expect(
        SupabaseSyncService.snapshotIsEmpty({
          'expenses': [
            {'id': 'e1'},
          ],
        }),
        isFalse,
      );
    });
  });

  group('resolveTransactionTime', () {
    final delivered = DateTime(2026, 8, 1, 18, 13);

    test('falls back when the message states no date', () {
      expect(resolveTransactionTime(null, fallback: delivered), delivered);
      expect(resolveTransactionTime('', fallback: delivered), delivered);
      expect(resolveTransactionTime('null', fallback: delivered), delivered);
      expect(
        resolveTransactionTime('sometime', fallback: delivered),
        delivered,
      );
    });

    test('uses the stated timestamp when the message carries one', () {
      expect(
        resolveTransactionTime('2026-07-30T14:22:00', fallback: delivered),
        DateTime(2026, 7, 30, 14, 22),
      );
    });

    test('a date-only answer keeps the delivery clock time', () {
      expect(
        resolveTransactionTime('2026-07-30', fallback: delivered),
        DateTime(2026, 7, 30, 18, 13),
      );
    });

    test('implausible dates are ignored', () {
      final future = DateTime.now().add(const Duration(days: 30));
      expect(
        resolveTransactionTime(future.toIso8601String(), fallback: delivered),
        delivered,
      );
      expect(
        resolveTransactionTime('1999-01-01T10:00:00', fallback: delivered),
        delivered,
      );
    });
  });
}
