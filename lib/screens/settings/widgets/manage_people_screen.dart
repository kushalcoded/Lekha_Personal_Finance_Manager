import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/people/people_providers.dart';
import '../../../widgets/common/glass.dart';

/// Who the split sheet offers you. The list ranks itself by how often and how
/// recently you split with someone; this screen is the manual override — and
/// the only way back from hiding a name.
class ManagePeopleScreen extends ConsumerWidget {
  const ManagePeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(allKnownPeopleProvider);
    final prefs = ref.watch(peoplePrefsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('People'), elevation: 0),
      body: people.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Names appear here once you split an expense or record a '
                  'debt.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: people.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Pinned names lead the split suggestions. Hidden ones '
                      'are never offered — their history is untouched either '
                      'way.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  );
                }
                final name = people[index - 1];
                return _PersonRow(
                  name: name,
                  isPinned: prefs.isPinned(name),
                  isHidden: prefs.isHidden(name),
                  onPin: () =>
                      ref.read(peoplePrefsProvider.notifier).togglePin(name),
                  onHide: () =>
                      ref.read(peoplePrefsProvider.notifier).toggleHide(name),
                );
              },
            ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final String name;
  final bool isPinned;
  final bool isHidden;
  final VoidCallback onPin;
  final VoidCallback onHide;

  const _PersonRow({
    required this.name,
    required this.isPinned,
    required this.isHidden,
    required this.onPin,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        radius: 12,
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isHidden ? cs.onSurfaceVariant : null,
                    ),
                  ),
                  if (isPinned || isHidden) ...[
                    const SizedBox(height: 2),
                    Text(
                      isPinned ? 'Pinned' : 'Hidden',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isPinned ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onPin,
              tooltip: isPinned ? 'Unpin' : 'Pin to the front',
              icon: Icon(
                isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: isPinned ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            IconButton(
              onPressed: onHide,
              tooltip: isHidden ? 'Show again' : 'Hide from suggestions',
              icon: Icon(
                isHidden
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: isHidden ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
