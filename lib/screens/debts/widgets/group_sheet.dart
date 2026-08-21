import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../providers/auth/auth_provider.dart';
import '../../../providers/people/people_providers.dart';
import '../../../providers/share/share_providers.dart';
import '../../../widgets/common/form_bits.dart';
import '../../../widgets/common/glass.dart';
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

class _MemberRow extends StatelessWidget {
  final SharedGroupMember member;
  final SharedGroup group;

  const _MemberRow({required this.member, required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 12,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                member.name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: member.link));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("${member.name}'s link copied")),
                );
              },
            ),
            IconButton(
              tooltip: 'Share link',
              icon: const Icon(Icons.share_rounded, size: 18),
              onPressed: () => SharePlus.instance.share(
                ShareParams(
                  text:
                      '${group.title} — what everyone owes, kept up to date: '
                      '${member.link}\n\n'
                      'No app needed — you pick a 4-digit PIN the first time.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
