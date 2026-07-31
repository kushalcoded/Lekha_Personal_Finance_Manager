import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/sms/sms_providers.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common/glass.dart';

/// Friendly, numbered walkthrough for wiring the iPhone Shortcuts automation
/// that forwards bank SMS into Lekha (docs: SETUP_IOS_SMS.md).
class IphoneSmsGuideScreen extends ConsumerStatefulWidget {
  const IphoneSmsGuideScreen({super.key});

  @override
  ConsumerState<IphoneSmsGuideScreen> createState() =>
      _IphoneSmsGuideScreenState();
}

class _IphoneSmsGuideScreenState extends ConsumerState<IphoneSmsGuideScreen> {
  String? _token;
  DateTime? _lastAt;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sms = ref.read(smsCaptureServiceProvider);
    final token = await sms.ensureIngestToken();
    final lastAt = await sms.lastCloudSmsAt();
    if (!mounted) return;
    setState(() {
      _token = token;
      _lastAt = lastAt;
      _loading = false;
    });
  }

  String get _endpoint =>
      '${dotenv.env['SUPABASE_URL'] ?? ''}/functions/v1/ingest-sms';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('iPhone SMS capture')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                GlassCard(
                  radius: 12,
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'iPhones don\'t let apps read SMS. The workaround: a tiny '
                    'automation on your iPhone forwards bank messages to '
                    'Lekha\'s secure inbox. One-time setup, about 3 minutes.',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
                const SizedBox(height: 14),
                _HealthCard(lastAt: _lastAt),
                const SizedBox(height: 18),
                if (_token == null)
                  GlassCard(
                    radius: 12,
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Couldn\'t load your setup values — check that you are '
                      'online, then reopen this screen.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.error,
                      ),
                    ),
                  )
                else ...[
                  _Step(
                    number: 1,
                    title: 'Open the Shortcuts app on the iPhone',
                    body:
                        'It comes pre-installed — swipe down on the home '
                        'screen and search "Shortcuts".',
                  ),
                  _Step(
                    number: 2,
                    title: 'Create the trigger',
                    body:
                        'Go to the Automation tab → tap + → choose Message.\n'
                        '• "Message Contains": type debited\n'
                        '• Select Run Immediately (not "Run After '
                        'Confirmation")\n'
                        '• Tap Next.',
                  ),
                  _Step(
                    number: 3,
                    title: 'Add the action',
                    body:
                        'Search for the action "Get Contents of URL" and add '
                        'it. Paste this as the URL:',
                    copyLabel: 'URL',
                    copyValue: _endpoint,
                  ),
                  _Step(
                    number: 4,
                    title: 'Set method and body',
                    body:
                        'Tap the small arrow on the action:\n'
                        '• Method: POST\n'
                        '• Request Body: JSON',
                  ),
                  _Step(
                    number: 5,
                    title: 'Add two Text fields',
                    body:
                        'First field — key: token, value: paste this '
                        '(it\'s your personal key, keep it private):',
                    copyLabel: 'token',
                    copyValue: _token!,
                  ),
                  _Step(
                    number: 6,
                    title: 'The second field is special',
                    body:
                        'Key: body. For the value, DON\'T type anything — tap '
                        'the value box, then tap the blue "Shortcut Input" '
                        'chip that appears above the keyboard. A blue pill '
                        'should sit in the box. That pill means "the incoming '
                        'SMS text".',
                  ),
                  _Step(
                    number: 7,
                    title: 'Test it',
                    body:
                        'Tap Done, then have someone text you a message '
                        'containing the word "debited" (or wait for a real '
                        'bank SMS). Open Lekha → Expenses: a Detected card '
                        'appears within seconds. The status box above turns '
                        'green once the first SMS lands.',
                  ),
                  const SizedBox(height: 10),
                  GlassCard(
                    radius: 12,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good to know',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '• Banks word SMS differently — repeat steps 2–7 '
                          'for "spent" and "withdrawn" if some spends are '
                          'missed. Lekha filters out non-bank messages.\n'
                          '• iOS sometimes switches automations off after '
                          'updates. If the status above looks stale, open '
                          'Shortcuts and check the automation is still on.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  final DateTime? lastAt;

  const _HealthCard({required this.lastAt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);

    final String label;
    final Color color;
    if (lastAt == null) {
      label = 'No SMS received from an iPhone yet.';
      color = cs.onSurfaceVariant;
    } else {
      final diff = DateTime.now().difference(lastAt!);
      final when = diff.inMinutes < 1
          ? 'just now'
          : diff.inMinutes < 60
          ? '${diff.inMinutes} min ago'
          : diff.inHours < 24
          ? '${diff.inHours} h ago'
          : '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
      final stale = diff.inDays >= 3;
      label = stale
          ? 'Last SMS received $when — if the iPhone has had bank SMS since, '
                'iOS may have disabled the automation. Open Shortcuts and '
                'check.'
          : 'Working — last SMS received $when.';
      color = stale ? cs.error : calm.positive;
    }

    return GlassCard(
      radius: 12,
      padding: const EdgeInsets.all(14),
      border: Border.all(color: color.withValues(alpha: 0.35)),
      child: Row(
        children: [
          Icon(Icons.monitor_heart_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String body;
  final String? copyLabel;
  final String? copyValue;

  const _Step({
    required this.number,
    required this.title,
    required this.body,
    this.copyLabel,
    this.copyValue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        radius: 12,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withValues(alpha: 0.16),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    '$number',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            if (copyValue != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A21),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        copyValue!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      tooltip: 'Copy $copyLabel',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: copyValue!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$copyLabel copied')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
