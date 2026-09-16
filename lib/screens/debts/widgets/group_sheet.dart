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
import '../person_ledger_screen.dart';
import '../../expenses/utils/split_helpers.dart';
import '../../expenses/utils/split_persistence.dart';
import '../../expenses/widgets/add_expense_modal.dart';
import '../../../models/expense/expense_model.dart';
import '../../../providers/storage/storage_providers.dart';
import 'shared_entry_card.dart';
import '../../../widgets/common/top_notice.dart';

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
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  // The same form as every other expense, opened already split
                  // with the group — so it gets a category, a payment method
                  // and the budget check, and there is one way to add a bill.
                  onPressed: () => showAddExpenseModal(
                    context,
                    initialSplit: SplitConfig(
                      people: group.members.map((m) => m.name).toList(),
                      groupId: group.id,
                    ),
                  ),
                  child: const Text('Add an expense'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => showPastSplitsSheet(context, group),
                child: const Text('Add past splits'),
              ),
            ],
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
                    try {
                      await acceptSharedEntry(
                        ref: ref,
                        entry: e,
                        userId: ref.read(currentUserIdProvider) ?? localUserId,
                        ownerName: ownerName,
                      );
                    } catch (err) {
                      showNotice('Could not add that: $err');
                      return;
                    }
                    showNotice('Added');
                  },
                  onDismiss: () async {
                    try {
                      await ref
                          .read(sharedInboxProvider.notifier)
                          .decide(e, 'dismissed');
                    } catch (err) {
                      showNotice('Could not dismiss that: $err');
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
          // Kept at the very bottom, away from everything you do routinely,
          // and worded as a plain sentence rather than an icon.
          const SizedBox(height: 24),
          Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _confirmDelete(context, ref, group),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Delete this group'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Deleting a group takes its page down for everyone, so the dialog says what
/// survives before it says what goes — the worry is always "do I lose the
/// bills?", and the answer is no.
Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  SharedGroup group,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${group.title}"?'),
      content: const Text(
        'The bills stay in your expenses and the debts stay on each '
        "person's page.\n\nThe group's page stops working for everyone, and "
        "the links you sent them won't open again. This can't be undone.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Keep it'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          child: const Text('Delete group'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final ok = await ref.read(sharedInboxProvider.notifier).deleteGroup(group);
  if (!context.mounted) return;
  if (ok) {
    Navigator.of(context).pop();
    showNotice('"${group.title}" deleted');
  } else {
    // The page lives online, so there is nothing sensible to queue: a group
    // half-deleted on this device only would still be live for everyone else.
    showNotice('Could not delete that — the group page needs a connection');
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
    await action();
    await markShareLinkSent(widget.member.token);
    if (!mounted) return;
    setState(() {});
    showNotice(done);
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
            const SizedBox(height: 2),
            Text(
              'Tap a name to settle up — group debts become ordinary '
              'receivables and payables once they land.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            ...ledger.members.map((name) {
              final value = ledger.netFor(name);
              // Tapping opens their own ledger, which is where Record a
              // payment already lives — a group's debts are ordinary
              // receivables and payables once they land.
              return InkWell(
                onTap: name == you
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PersonLedgerScreen(person: name),
                        ),
                      ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
                      if (name != you) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: cs.outline,
                        ),
                      ],
                    ],
                  ),
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

/// Split expenses from before the group existed, posted to it in a tap.
///
/// Nothing is re-entered and nothing in your books changes: the debts already
/// exist, and this only puts the bills on the group's page.
Future<void> showPastSplitsSheet(BuildContext context, SharedGroup group) {
  return showResponsiveSheet(
    context,
    mobileChild: _PastSplits(group: group),
    desktopChild: _PastSplits(group: group),
  );
}

/// A split expense that could go on [group], rebuilt from the debts it made.
class _Candidate {
  final Expense expense;
  final SplitConfig config;
  final SplitResult split;

  const _Candidate(this.expense, this.config, this.split);
}

class _PastSplits extends ConsumerStatefulWidget {
  final SharedGroup group;

  const _PastSplits({required this.group});

  @override
  ConsumerState<_PastSplits> createState() => _PastSplitsState();
}

class _PastSplitsState extends ConsumerState<_PastSplits> {
  late final Future<Set<String>> _linked = ref
      .read(sharedInboxProvider.notifier)
      .allLinkedExpenseIds();
  final Set<String> _picked = {};
  bool _saving = false;

  /// Everyone on it must be on the group — the page could not show a share for
  /// somebody who is not — and anything already settled is left alone, since
  /// the group page would show it owing with no way to record that payment.
  List<_Candidate> _candidates(Set<String> linked) {
    final out = <_Candidate>[];
    final expenses = [...ref.read(expensesProvider).expenses]
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final expense in expenses) {
      if (linked.contains(expense.id)) continue;
      final links = findSplitLinks(ref, expense.id);
      if (links.isEmpty || links.anySettled) continue;
      final recon = reconstructSplit(links, expense.amount);
      if (recon == null) continue;

      final names = <String>[];
      for (final person in recon.config.people) {
        final member = widget.group.memberNamed(person);
        if (member == null) break;
        names.add(member.name);
      }
      if (names.length != recon.config.people.length) continue;

      // Rebuilt with the group's spelling of every name, since its page
      // matches shares by exact name.
      final byGroupName = {
        for (var i = 0; i < names.length; i++)
          names[i]: recon.config.exact[recon.config.people[i]] ?? 0.0,
      };
      final payer = recon.config.paidBy == null
          ? null
          : widget.group.memberNamed(recon.config.paidBy!)?.name;
      final config = SplitConfig(
        people: names,
        paidBy: payer,
        mode: SplitMode.exact,
        exact: byGroupName,
        groupId: widget.group.id,
      );
      final split = computeSplit(
        total: recon.total,
        people: names,
        mode: SplitMode.exact,
        exactAmounts: byGroupName,
      );
      out.add(_Candidate(expense, config, split));
    }
    return out;
  }

  Future<void> _post(List<_Candidate> all) async {
    setState(() => _saving = true);
    final inbox = ref.read(sharedInboxProvider.notifier);
    var queued = 0;
    for (final c in all.where((c) => _picked.contains(c.expense.id))) {
      final entry = groupEntryForSplit(
        ownerName: widget.group.ownerName,
        config: c.config,
        split: c.split,
      );
      final note = (c.expense.description ?? '')
          .replaceAll(RegExp(r'\s*·?\s*Split ₹[\d,]+(\.\d+)?$'), '')
          .trim();
      final ok = await inbox.publishSplit(
        groupId: widget.group.id,
        expenseId: c.expense.id,
        total: entry.total,
        payerName: entry.payer,
        shares: entry.shares,
        note: note.isEmpty ? c.expense.category : note,
        date: c.expense.date,
      );
      if (!ok) queued++;
    }
    if (!mounted) return;
    final count = _picked.length;
    Navigator.of(context).pop();
    showNotice(
      queued > 0
          ? '$count ${AppFormatters.plural(count, 'bill', 'bills')} saved · '
                'they go on ${widget.group.title} when you are back online'
          : 'Added $count ${AppFormatters.plural(count, 'bill', 'bills')} '
                'to ${widget.group.title}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return FutureBuilder<Set<String>>(
      future: _linked,
      builder: (context, snap) {
        final Widget body;
        List<_Candidate> candidates = const [];
        if (snap.hasError) {
          body = Text(
            'Could not check which bills are already on a group. '
            'Check your connection and try again.',
            style: theme.textTheme.bodyMedium,
          );
        } else if (!snap.hasData) {
          body = const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        } else {
          candidates = _candidates(snap.data!);
          body = candidates.isEmpty
              ? Text(
                  'No earlier splits with only people from '
                  '${widget.group.title}.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                )
              : Column(
                  children: [
                    for (final c in candidates)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _picked.contains(c.expense.id),
                        onChanged: _saving
                            ? null
                            : (on) => setState(
                                () => on == true
                                    ? _picked.add(c.expense.id)
                                    : _picked.remove(c.expense.id),
                              ),
                        title: Text(
                          (c.expense.description ?? c.expense.category)
                              .replaceAll(
                                RegExp(r'\s*·?\s*Split ₹[\d,]+(\.\d+)?$'),
                                '',
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${AppFormatters.formatDate(c.expense.date)} · '
                          '${AppFormatters.formatCurrency(c.split.myShare + c.split.othersTotal)}'
                          ' with ${c.config.people.join(', ')}',
                        ),
                      ),
                  ],
                );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add past splits',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Bills you already split with people in '
                '${widget.group.title}. Ticking them puts them on the group '
                'page; what you are owed stays the same.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              body,
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _picked.isEmpty || _saving
                    ? null
                    : () => _post(candidates),
                child: Text(
                  _picked.isEmpty
                      ? 'Pick bills to add'
                      : 'Add ${_picked.length} to ${widget.group.title}',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
