import '../../utils/amount_expression.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/ai_providers.dart';
import '../../providers/storage/storage_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters/formatters.dart';
import '../../widgets/common/glass.dart';
import '../payables/widgets/payable_settlement_modal.dart';
import '../receivables/widgets/receivable_settlement_modal.dart';
import 'providers/people_balance_providers.dart';

/// Everything you and one person owe each other, in one ledger.
class PersonLedgerScreen extends ConsumerWidget {
  final String person;

  const PersonLedgerScreen({super.key, required this.person});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(person)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          GlassCard(
            radius: 18,
            padding: const EdgeInsets.all(16),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                netColor.withValues(alpha: 0.18),
                const Color(0xFF131318).withValues(alpha: 0.42),
              ],
            ),
            border: Border.all(color: netColor.withValues(alpha: 0.24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  net >= 0 ? 'Owes you' : 'You owe',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppFormatters.formatCurrency(net.abs()),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: netColor,
                  ),
                ),
                if (balance.owedToYou > 0 && balance.youOwe > 0) ...[
                  const SizedBox(height: 6),
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
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () => _recordPayment(context, ref, balance),
              icon: const Icon(Icons.payments_rounded, size: 18),
              label: Text(
                net >= 0 ? 'Record a payment' : 'Record what you paid',
              ),
            ),
          ),
          if (net > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _sendReminder(context, ref, balance),
                icon: const Icon(Icons.waving_hand_rounded, size: 18),
                label: const Text('Send a gentle reminder'),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Ledger',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Swipe an entry to settle it.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
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
    return AlertDialog(
      title: const Text('Reminder preview'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.canRegenerate) ...[
            Wrap(
              spacing: 8,
              children: _languages.map((lang) {
                return ChoiceChip(
                  label: Text(lang),
                  selected: _language == lang,
                  onSelected: _loading
                      ? null
                      : (_) {
                          if (_language == lang) return;
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.canRegenerate)
          TextButton.icon(
            onPressed: _loading ? null : _draft,
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

class _LedgerRow extends StatelessWidget {
  final PersonLedgerItem item;
  final VoidCallback onSettle;

  const _LedgerRow({required this.item, required this.onSettle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final color = item.isReceivable ? calm.positive : cs.error;
    final when = DateFormat('MMM d').format(item.date);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        enabled: !item.settled,
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.3,
          children: [
            SlidableAction(
              onPressed: (_) => onSettle(),
              backgroundColor: calm.positive,
              foregroundColor: Colors.white,
              icon: Icons.check_rounded,
              label: item.isReceivable ? 'Received' : 'Settle',
              borderRadius: BorderRadius.circular(14),
            ),
          ],
        ),
        child: GlassCard(
          radius: 14,
          padding: const EdgeInsets.all(12),
          child: Opacity(
            opacity: item.settled ? 0.5 : 1,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    item.isReceivable
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    size: 17,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
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
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.settled
                            ? '$when · settled'
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
                  '${item.isReceivable ? '+' : '-'}${AppFormatters.formatCurrency(item.amount)}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: item.settled ? cs.onSurfaceVariant : color,
                    decoration: item.settled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
