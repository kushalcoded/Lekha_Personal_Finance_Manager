import '../../utils/amount_expression.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/share/shared_entry.dart';
import '../../providers/ai_providers.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/clock_provider.dart';
import '../../providers/share/share_providers.dart';
import '../../providers/storage/storage_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters/formatters.dart';
import '../../widgets/common/form_bits.dart';
import '../../widgets/common/glass.dart';
import '../payables/widgets/payable_settlement_modal.dart';
import '../receivables/widgets/receivable_settlement_modal.dart';
import '../settings/providers/settings_providers.dart';
import 'providers/people_balance_providers.dart';
import 'widgets/shared_entry_card.dart';

/// Everything you and one person owe each other, in one ledger.
class PersonLedgerScreen extends ConsumerWidget {
  final String person;

  const PersonLedgerScreen({super.key, required this.person});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final inbox = ref.watch(sharedInboxProvider);
    final waiting = inbox.forPerson(person);
    final resets = inbox.resetsForPerson(person);
    final balance = ref.watch(personBalanceProvider(person));

    if (balance == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(person)),
        body: Center(
          child: Text(
            'All settled with $person.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final net = balance.net;
    final netColor = net >= 0 ? calm.positive : cs.error;
    final open = balance.items.where((i) => !i.settled).toList();
    // Through nowProvider, not DateTime.now(): this is the one number on the
    // screen that changes on its own overnight, which re-shot the golden every
    // single day.
    final oldestDays = open.isEmpty
        ? 0
        : ref
              .read(nowProvider)()
              .difference(
                open.map((i) => i.date).reduce((a, b) => a.isBefore(b) ? a : b),
              )
              .inDays;
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF1A1A21),
              child: Text(
                person.isEmpty ? '?' : person[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(person),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Share this page',
            icon: const Icon(Icons.link_rounded),
            onPressed: () => _shareLedger(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (waiting.isNotEmpty || resets.isNotEmpty) ...[
            const FieldLabel('From the shared page'),
            const SizedBox(height: 4),
            Text(
              'Nothing here is in your ledger yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            ...resets.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PinResetCard(
                  request: r,
                  onAllow: () => _allowReset(context, ref, r),
                  onDismiss: () =>
                      ref.read(sharedInboxProvider.notifier).dismissReset(r),
                ),
              ),
            ),
            ...waiting.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SharedEntryCard(
                  entry: e,
                  ownerName: ref.read(settingsProvider).displayName,
                  onAccept: () => _acceptEntry(context, ref, e),
                  onDismiss: () => ref
                      .read(sharedInboxProvider.notifier)
                      .decide(e, 'dismissed'),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          GlassCard(
            radius: 12,
            padding: const EdgeInsets.all(16),
            color: netColor.withValues(alpha: 0.08),
            border: Border.all(color: netColor.withValues(alpha: 0.30)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FieldLabel(net >= 0 ? 'Owes you' : 'You owe'),
                const SizedBox(height: 6),
                Text(
                  AppFormatters.formatCurrency(net.abs()),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: netColor,
                  ),
                ),
                if (open.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${open.length} ${open.length == 1 ? 'item' : 'items'}'
                    ' · oldest $oldestDays ${oldestDays == 1 ? 'day' : 'days'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (balance.owedToYou > 0 && balance.youOwe > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Net of ${AppFormatters.formatCurrency(balance.owedToYou)} owed to you '
                    'and ${AppFormatters.formatCurrency(balance.youOwe)} you owe',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Mockup: iconless buttons — paired on desktop, stacked on phone.
          if (isWide && net > 0)
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _recordPayment(context, ref, balance),
                    child: const Text('Record a payment'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _sendReminder(context, ref, balance),
                    child: const Text('Send reminder'),
                  ),
                ),
              ],
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _recordPayment(context, ref, balance),
                child: Text(
                  net >= 0 ? 'Record a payment' : 'Record what you paid',
                ),
              ),
            ),
            if (net > 0) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _sendReminder(context, ref, balance),
                  child: const Text('Send a gentle reminder'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 18),
          FieldLabel(isWide ? 'Ledger' : 'Ledger · swipe to settle'),
          const SizedBox(height: 10),
          SlidableAutoCloseBehavior(
            child: Column(
              children: balance.items
                  .map(
                    (item) => _LedgerRow(
                      item: item,
                      onSettle: () => _settle(context, ref, item),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Create (or reuse) this person's share link and hand it to the share
  /// sheet. Deliberately its own action rather than being appended to the AI
  /// reminder: a link buried at the end of a nudge about money reads like the
  /// nudge, and this is an invitation.
  Future<void> _shareLedger(BuildContext context, WidgetRef ref) async {
    final ownerName = ref.read(settingsProvider).displayName.trim();
    if (ownerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add your name in Settings first, so they know who shared it.',
          ),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final link = await ref
        .read(sharedInboxProvider.notifier)
        .shareLinkFor(person, ownerName: ownerName);
    if (link == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not make a link. Check you are signed in.'),
        ),
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Here is what we owe each other, kept up to date: $link\n\n'
            'No app needed — you pick a 4-digit PIN the first time.',
      ),
    );
  }

  Future<void> _acceptEntry(
    BuildContext context,
    WidgetRef ref,
    SharedEntry entry,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await acceptSharedEntry(
      ref: ref,
      entry: entry,
      userId: ref.read(currentUserIdProvider) ?? localUserId,
      ownerName: ref.read(settingsProvider).displayName,
    );
    messenger.showSnackBar(const SnackBar(content: Text('Added')));
  }

  Future<void> _allowReset(
    BuildContext context,
    WidgetRef ref,
    PinResetRequest request,
  ) async {
    final inbox = ref.read(sharedInboxProvider.notifier);
    final version = await inbox.pinVersionOf(request);
    await inbox.allowReset(request, bumpTo: version + 1);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${request.name} can set a new PIN now')),
    );
  }

  /// Ask Gemini to draft a warm, no-name nudge from the open items, show it in
  /// a preview the user can regenerate, then hand the chosen text to the share
  /// sheet — the user picks WhatsApp, SMS, or anything else, then the contact
  /// (we don't store phone numbers). Falls back to a plain template if Gemini
  /// isn't configured or a call fails.
  Future<void> _sendReminder(
    BuildContext context,
    WidgetRef ref,
    PersonBalance balance,
  ) async {
    final open = balance.items
        .where((i) => i.isReceivable && !i.settled)
        .toList();
    final items = open.map((i) {
      final what = i.note?.isNotEmpty == true ? i.note! : 'a shared expense';
      final when = DateFormat('MMM d').format(i.date);
      return '$what · ${AppFormatters.formatCurrency(i.amount)} ($when)';
    }).toList();
    final total = AppFormatters.formatCurrency(balance.owedToYou);
    final service = ref.read(geminiServiceProvider);

    Future<String> draft(String language) async {
      if (!service.isConfigured) return _reminderTemplate(total, items);
      try {
        return await service.draftDebtReminder(
          total: total,
          items: items,
          language: language,
        );
      } catch (_) {
        return _reminderTemplate(total, items);
      }
    }

    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => _ReminderPreviewDialog(
        canRegenerate: service.isConfigured,
        draft: draft,
      ),
    );
    if (message == null) return; // cancelled
    await SharePlus.instance.share(ShareParams(text: message));
  }

  String _reminderTemplate(String total, List<String> items) {
    final body = StringBuffer()
      ..writeln('Hi 🙂')
      ..writeln()
      ..writeln(
        'Just a little reminder about $total whenever it\'s convenient — '
        'no rush at all!',
      );
    if (items.isNotEmpty) {
      body
        ..writeln()
        ..writeln(items.map((i) => '• $i').join('\n'));
    }
    body
      ..writeln()
      ..write('Thanks so much! 🙏');
    return body.toString();
  }

  Future<void> _settle(
    BuildContext context,
    WidgetRef ref,
    PersonLedgerItem item,
  ) async {
    // Both sides now support partial settlement via their own modal.
    if (item.isReceivable) {
      await showReceivableSettlementModal(
        context,
        receivable: item.receivable!,
      );
    } else {
      await showPayableSettlementModal(context, payable: item.payable!);
    }
  }

  /// A lump payment from/to the person, waterfalled across their open debts
  /// oldest-first. Direction follows the net balance.
  Future<void> _recordPayment(
    BuildContext context,
    WidgetRef ref,
    PersonBalance balance,
  ) async {
    final theyOweYou = balance.net >= 0;
    // Prefilled with the full outstanding amount — most payments settle in
    // full; edit it for a partial one.
    final amountCtrl = TextEditingController(
      text: balance.net.abs().toStringAsFixed(2),
    );
    final noteCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          theyOweYou ? '${balance.name} paid you' : 'You paid ${balance.name}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                prefixText: '₹',
                hintText: 'Amount',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(hintText: 'Note (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final amount = parseAmountExpression(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) return;
    final note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();

    if (theyOweYou) {
      await ref
          .read(receivablesProvider.notifier)
          .settlePersonReceivables(balance.name, amount, note: note);
    } else {
      await ref
          .read(payablesProvider.notifier)
          .settlePersonPayables(balance.name, amount, note: note);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Payment recorded')));
  }
}

/// Shows the drafted reminder with a language picker, Regenerate (when AI is
/// on), and Share. Pops the chosen text, or null if cancelled. Editable inline.
class _ReminderPreviewDialog extends StatefulWidget {
  final bool canRegenerate;
  final Future<String> Function(String language) draft;

  const _ReminderPreviewDialog({
    required this.canRegenerate,
    required this.draft,
  });

  @override
  State<_ReminderPreviewDialog> createState() => _ReminderPreviewDialogState();
}

class _ReminderPreviewDialogState extends State<_ReminderPreviewDialog> {
  static const _languages = ['English', 'Hinglish', 'Hindi'];
  final _controller = TextEditingController();
  String _language = 'English';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _draft();
  }

  Future<void> _draft() async {
    setState(() => _loading = true);
    final text = await widget.draft(_language);
    if (!mounted) return;
    setState(() {
      _controller.text = text;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AlertDialog(
      title: const Text(
        'Send a reminder',
        style: TextStyle(
          fontFamily: 'Space Grotesk',
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.canRegenerate) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _languages.map((lang) {
                return ChoicePill(
                  label: lang == 'Hindi' ? 'हिन्दी' : lang,
                  selected: _language == lang,
                  onTap: () {
                    if (_loading || _language == lang) return;
                    setState(() => _language = lang);
                    _draft();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          _loading
              ? const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                )
              : TextField(
                  controller: _controller,
                  maxLines: null,
                  minLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Drafted by AI · no name included · edit before sending',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.canRegenerate)
          OutlinedButton.icon(
            onPressed: _loading ? null : _draft,
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.onSurface,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Regenerate'),
          ),
        FilledButton.icon(
          onPressed: _loading
              ? null
              : () => Navigator.of(context).pop(_controller.text),
          icon: const Icon(Icons.share_rounded, size: 18),
          label: const Text('Share'),
        ),
      ],
    );
  }
}

class _LedgerRow extends StatefulWidget {
  final PersonLedgerItem item;
  final VoidCallback onSettle;

  const _LedgerRow({required this.item, required this.onSettle});

  @override
  State<_LedgerRow> createState() => _LedgerRowState();
}

class _LedgerRowState extends State<_LedgerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final item = widget.item;
    final color = item.isReceivable ? calm.positive : cs.error;
    final when = DateFormat('MMM d').format(item.date);
    // Desktop has no swipe — the settle check appears on hover instead.
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        enabled: !item.settled,
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.3,
          children: [
            SlidableAction(
              onPressed: (_) => widget.onSettle(),
              backgroundColor: calm.positive,
              foregroundColor: Colors.white,
              icon: Icons.check_rounded,
              label: item.isReceivable ? 'Received' : 'Settle',
              borderRadius: BorderRadius.circular(14),
            ),
          ],
        ),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GlassCard(
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Opacity(
              opacity: item.settled ? 0.45 : 1,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.note?.isNotEmpty == true
                              ? item.note!
                              : (item.isReceivable ? 'Owes you' : 'You owe'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            decoration: item.settled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.settled
                              ? 'Settled $when'
                              : item.isOverdue
                              ? '$when · overdue'
                              : when,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: item.isOverdue && !item.settled
                                ? cs.error
                                : cs.onSurfaceVariant,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppFormatters.formatCurrency(item.amount),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: item.settled ? cs.onSurfaceVariant : color,
                      decoration: item.settled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (!item.settled && wide && _hover) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: widget.onSettle,
                      tooltip: item.isReceivable ? 'Mark received' : 'Settle',
                      icon: Icon(
                        Icons.check_circle_outline_rounded,
                        size: 19,
                        color: cs.onSurfaceVariant,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
