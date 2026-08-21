import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history/cycle_history_snapshot.dart';
import '../providers/ai_providers.dart';
import '../utils/formatters/formatters.dart';
import '../widgets/common/ai_text.dart';
import 'history_providers.dart';

/// Feature 6: after a salary-cycle reset, show an AI recap of the cycle that
/// was just archived. No-op when there is no archived cycle yet. Falls back to
/// a local summary when Gemini is unconfigured or fails (offline-first).
Future<void> showCycleResetRecap(BuildContext context, WidgetRef ref) async {
  final snapshot = ref.read(latestCycleHistoryProvider);
  if (snapshot == null) return;

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Last cycle wrapped up'),
      content: Consumer(
        builder: (context, ref, _) {
          final recap = ref.watch(historyAiSummaryProvider(snapshot));
          return recap.when(
            data: (text) => AiText(
              (text == null || text.trim().isEmpty)
                  ? _localRecap(snapshot)
                  : text.trim(),
            ),
            loading: () => const SizedBox(
              height: 64,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => Text(_localRecap(snapshot)),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

String _localRecap(CycleHistorySnapshot snapshot) {
  final spent = AppFormatters.formatCurrency(snapshot.totalExpenses);
  final budget = AppFormatters.formatCurrency(snapshot.cycleBudget);
  final base = snapshot.cycleBudget > 0
      ? 'You spent $spent of your $budget budget'
      : 'You spent $spent';
  final n = snapshot.transactionCount;
  return '$base across $n ${AppFormatters.plural(n, 'transaction', 'transactions')}.';
}
