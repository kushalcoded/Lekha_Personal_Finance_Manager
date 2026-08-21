import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../providers/auth/auth_provider.dart';
import '../../../providers/people/people_providers.dart';
import '../../../providers/share/share_providers.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common/form_bits.dart';
import '../../../widgets/common/glass.dart';
import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/person_menu.dart';
import '../../../widgets/responsive/responsive_sheet.dart';
import '../../settings/providers/settings_providers.dart';
import 'shared_entry_card.dart';

/// Start a group: a name and the people in it.
///
/// A group is not a new kind of thing in the app — it is a shared space with a
/// title and more than one person on it. The owner's own books stay the same
/// pairwise debts they always were; only the page nets everyone out.
Future<void> showNewGroupSheet(BuildContext context) {
  return showResponsiveSheet(
    context,
    mobileChild: const _NewGroupForm(),
    desktopChild: const _NewGroupForm(),
  );
}

class _NewGroupForm extends ConsumerStatefulWidget {
  const _NewGroupForm();

  @override
  ConsumerState<_NewGroupForm> createState() => _NewGroupFormState();
}

class _NewGroupFormState extends ConsumerState<_NewGroupForm> {
  final _title = TextEditingController();
  final _name = TextEditingController();
  final List<String> _people = [];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _name.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return;
    if (_people.any((p) => p.toLowerCase() == name.toLowerCase())) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _people.add(name);
      _name.clear();
    });
  }

  Future<void> _create() async {
    final ownerName = ref.read(settingsProvider).displayName.trim();
    if (ownerName.isEmpty) {
      setState(() => _error = 'Add your name in Settings first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await ref
        .read(sharedInboxProvider.notifier)
        .createGroup(_title.text, _people, ownerName: ownerName);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error = 'Could not create it. Check you are signed in.';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final prefs = ref.watch(peoplePrefsProvider);
    final known = ref
        .watch(knownPeopleProvider)
        .where((n) => !_people.any((p) => p.toLowerCase() == n.toLowerCase()))
        .toList();
    final canSave =
        _title.text.trim().isNotEmpty && _people.isNotEmpty && !_saving;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New group',
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Everyone gets their own link. They see the whole group and can '
            'add to it — anything involving you comes back for you to accept.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          const FieldLabel('CALLED'),
          const SizedBox(height: 6),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Goa trip'),
          ),
          const SizedBox(height: 18),
          const FieldLabel('WHO IS IN IT'),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: _add,
            decoration: InputDecoration(
              hintText: 'Add a name',
              prefixIcon: const Icon(Icons.person_add_alt_rounded, size: 18),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _add(_name.text),
              ),
            ),
          ),
          if (_people.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _people
                  .map(
                    (p) => ChoicePill(
                      label: p,
                      icon: Icons.close_rounded,
                      selected: true,
                      onTap: () => setState(() => _people.remove(p)),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (known.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: known
                  .map(
                    (n) => GestureDetector(
                      onLongPress: () => showPersonMenu(
                        context,
                        ref,
                        n,
                        isPinned: prefs.isPinned(n),
                      ),
                      child: ChoicePill(
                        label: n,
                        icon: prefs.isPinned(n)
                            ? Icons.push_pin_rounded
                            : Icons.add_rounded,
                        selected: false,
                        onTap: () => _add(n),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          const SizedBox(height: 22),
          GradientButton(
            label: _saving ? 'Creating…' : 'Create group',
            enabled: canSave,
            onPressed: _create,
          ),
        ],
      ),
    );
  }
}

/// A group's links and anything waiting on the owner.
Future<void> showGroupSheet(BuildContext context, SharedGroup group) {
  return showResponsiveSheet(
    context,
    mobileChild: _GroupDetail(group: group),
    desktopChild: _GroupDetail(group: group),
  );
}

class _GroupDetail extends ConsumerWidget {
  final SharedGroup group;

  const _GroupDetail({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final waiting = ref.watch(sharedInboxProvider).forSpace(group.id);
    final ownerName = ref.read(settingsProvider).displayName;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${group.members.length} '
            '${group.members.length == 1 ? 'person' : 'people'} · each link is '
            'personal, so send the right one to the right person.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          _GroupStanding(spaceId: group.id),
          if (waiting.isNotEmpty) ...[
            const SizedBox(height: 20),
            const FieldLabel('Waiting for you'),
            const SizedBox(height: 10),
            ...waiting.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SharedEntryCard(
                  entry: e,
                  ownerName: ownerName,
                  onAccept: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await acceptSharedEntry(
                        ref: ref,
                        entry: e,
                        userId: ref.read(currentUserIdProvider) ?? localUserId,
                        ownerName: ownerName,
                      );
                    } catch (err) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Could not add that: $err')),
                      );
                      return;
                    }
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Added')),
                    );
                  },
                  onDismiss: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await ref
                          .read(sharedInboxProvider.notifier)
                          .decide(e, 'dismissed');
                    } catch (err) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Could not dismiss that: $err')),
                      );
                    }
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const FieldLabel('Links'),
          const SizedBox(height: 10),
          ...group.members.map((m) => _MemberRow(member: m, group: group)),
        ],
      ),
    );
  }
}

class _MemberRow extends ConsumerStatefulWidget {
  final SharedGroupMember member;
  final SharedGroup group;

  const _MemberRow({required this.member, required this.group});

  @override
  ConsumerState<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends ConsumerState<_MemberRow> {
  Future<void> _take(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    await action();
    await markShareLinkSent(widget.member.token);
    if (!mounted) return;
    setState(() {});
    messenger.showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final m = widget.member;
    final progress = shareProgressFor(
      sent: shareLinkSent(m.token),
      openedAt: m.openedAt,
      joinedAt: m.joinedAt,
    );
    final color = switch (progress) {
      ShareProgress.joined => calm.positive,
      ShareProgress.opened => calm.warning,
      ShareProgress.sent => cs.onSurfaceVariant,
      ShareProgress.notSent => cs.error,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 12,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // A dot rather than a word: four states across a list of names is
            // a lot of text, and the colour is the thing you scan for.
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    shareProgressLabel(progress),
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () => _take(
                () => Clipboard.setData(ClipboardData(text: m.link)),
                "${m.name}'s link copied",
              ),
            ),
            IconButton(
              tooltip: 'Share link',
              icon: const Icon(Icons.share_rounded, size: 18),
              onPressed: () => _take(
                () => SharePlus.instance.share(
                  ShareParams(
                    text:
                        '${widget.group.title} — what everyone owes, kept up '
                        'to date: ${m.link}\n\n'
                        'No app needed — you pick a 4-digit PIN the first time.',
                  ),
                ),
                'Shared with ${m.name}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where everyone stands, and the fewest payments that would settle it.
///
/// The owner has no share link, so without this the group's maths existed only
/// on the guests' pages and the person who created it could not see it at all.
class _GroupStanding extends ConsumerWidget {
  final String spaceId;

  const _GroupStanding({required this.spaceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final async = ref.watch(groupLedgerProvider(spaceId));
    final you = ref.read(settingsProvider).displayName.trim();

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (e, _) => Text(
        'Could not load the group just now.',
        style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
      ),
      data: (ledger) {
        if (ledger == null) return const SizedBox.shrink();
        final mine = ledger.netFor(you);
        final color = mine > 0.009
            ? calm.positive
            : mine < -0.009
            ? cs.error
            : cs.onSurfaceVariant;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassCard(
              radius: 12,
              padding: const EdgeInsets.all(14),
              color: color.withValues(alpha: 0.08),
              border: Border.all(color: color.withValues(alpha: 0.30)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FieldLabel(
                    mine > 0.009
                        ? 'The group owes you'
                        : mine < -0.009
                        ? 'You owe the group'
                        : "You're square",
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppFormatters.formatCurrency(mine.abs()),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            if (ledger.transfers.isNotEmpty) ...[
              const SizedBox(height: 16),
              const FieldLabel('Who pays whom'),
              const SizedBox(height: 6),
              ...ledger.transfers.map(
                (t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${t.from == you ? 'You' : t.from} → '
                          '${t.to == you ? 'you' : t.to}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        AppFormatters.formatCurrency(t.amount),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'The fewest payments that settle everyone.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            const FieldLabel('Everyone'),
            const SizedBox(height: 6),
            ...ledger.members.map((name) {
              final value = ledger.netFor(name);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name == you ? '$name (you)' : name,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      value > 0.009
                          ? 'is owed ${AppFormatters.formatCurrency(value)}'
                          : value < -0.009
                          ? 'owes ${AppFormatters.formatCurrency(-value)}'
                          : 'square',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: value > 0.009
                            ? calm.positive
                            : value < -0.009
                            ? cs.error
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (ledger.entries.isEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Nothing added yet. Anyone with a link can start.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
