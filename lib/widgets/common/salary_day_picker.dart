import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../screens/settings/providers/settings_providers.dart';

/// Ask which day of the month salary lands, and store the answer.
///
/// Lives here rather than in the Settings screen because three places ask it
/// now — Settings, the first-run sheet and the setup checklist — and the
/// wording matters: the day only decides *when Lekha asks* about a new cycle,
/// never when one rolls.
Future<void> pickSalaryDay(BuildContext context, WidgetRef ref) async {
  final current = ref.read(settingsProvider).salaryDay;
  final picked = await showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Salary day'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            'Which day of the month does your salary usually land? Lekha '
            'only uses it to ask about starting a new cycle — you always '
            'confirm the real date.',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ),
        SizedBox(
          height: 260,
          width: 320,
          child: GridView.count(
            crossAxisCount: 6,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (var day = 1; day <= 31; day++)
                InkWell(
                  onTap: () => Navigator.of(ctx).pop(day),
                  child: Center(
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontWeight: day == current
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: day == current
                            ? Theme.of(ctx).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (current != null)
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(-1),
            child: const Text("Don't ask me"),
          ),
      ],
    ),
  );
  if (picked == null) return;
  await ref
      .read(settingsProvider.notifier)
      .setSalaryDay(picked == -1 ? null : picked);
}
