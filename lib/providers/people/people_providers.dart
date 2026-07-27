import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage_providers.dart';

/// Everyone you've already tracked money with — pulled from existing
/// receivables and payables so the split picker can autocomplete names
/// instead of making you retype them.
final knownPeopleProvider = Provider<List<String>>((ref) {
  final receivables = ref.watch(receivablesProvider).receivables;
  final payables = ref.watch(payablesProvider).payables;

  final names = <String>{
    ...receivables.map((r) => r.fromPerson.trim()),
    ...payables.map((p) => p.toPerson.trim()),
  }..removeWhere((n) => n.isEmpty);

  final sorted = names.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return sorted;
});
