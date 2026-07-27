import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history/cycle_history_snapshot.dart';
import '../providers/auth/auth_provider.dart';
import '../providers/storage/storage_providers.dart';
import 'settings/providers/settings_providers.dart';

final cycleHistoryProvider =
    Provider.family<List<CycleHistorySnapshot>, String>((ref, userId) {
      ref.watch(settingsProvider);
      return ref.watch(hiveServiceProvider).getCycleHistory(userId);
    });

final latestCycleHistoryProvider = Provider<CycleHistorySnapshot?>((ref) {
  final userId = ref.watch(currentUserIdProvider) ?? '';
  final history = ref.watch(cycleHistoryProvider(userId));
  if (history.isEmpty) {
    return null;
  }
  return history.first;
});
