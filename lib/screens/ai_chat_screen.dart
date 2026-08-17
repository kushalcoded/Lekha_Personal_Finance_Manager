import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ai_providers.dart';
import '../widgets/common/ai_text.dart';
import '../widgets/common/form_bits.dart';
import '../widgets/common/glass.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(bool configured, bool loading) async {
    if (loading || !configured) return;
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    await ref.read(aiChatProvider.notifier).send(text);
  }

  Future<void> _sendQuick(String text, bool configured, bool loading) async {
    if (loading || !configured) return;
    await ref.read(aiChatProvider.notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(aiChatProvider);
    final configured = ref.watch(geminiConfiguredProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Assistant'),
            const SizedBox(width: 10),
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                'AI',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => ref.read(aiChatProvider.notifier).clear(),
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear chat',
          ),
        ],
      ),
      // Desktop: a centered column keeps chat lines readable on wide
      // monitors (mockup frame 11); no-op on phones.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              if (!configured)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _AiBanner(
                    text:
                        'AI is unavailable. Sign in and make sure the gemini-proxy function is deployed (see SETUP_AUTH.md).',
                  ),
                ),
              if (chat.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _AiBanner(text: chat.error!),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (chat.messages.isEmpty)
                      const _EmptyChatState()
                    else
                      ...chat.messages.map((message) {
                        final isUser = message.role == 'user';
                        return Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            constraints: const BoxConstraints(maxWidth: 520),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.14)
                                  : const Color(0xFF131318),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(12),
                                topRight: const Radius.circular(12),
                                bottomLeft: Radius.circular(isUser ? 12 : 3),
                                bottomRight: Radius.circular(isUser ? 3 : 12),
                              ),
                              border: Border.all(
                                color: isUser
                                    ? Theme.of(context).colorScheme.primary
                                          .withValues(alpha: 0.30)
                                    : Colors.white.withValues(alpha: 0.07),
                              ),
                            ),
                            child: AiText(message.text),
                          ),
                        );
                      }),
                    if (chat.isLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: CircularProgressIndicator(),
                        ),
                      ),
                  ],
                ),
              ),
              if (chat.pending != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: GlassCard(
                    radius: 12,
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.4),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${chat.pending!.summary}?',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              ref.read(aiChatProvider.notifier).cancelPending(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => ref
                              .read(aiChatProvider.notifier)
                              .confirmPending(),
                          child: const Text('Confirm'),
                        ),
                      ],
                    ),
                  ),
                ),
              // Mockup: quick-question chips sit just above the input.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    ChoicePill(
                      label: 'Budget left?',
                      selected: false,
                      onTap: () => _sendQuick(
                        'How much budget do I have left this cycle?',
                        configured,
                        chat.isLoading,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ChoicePill(
                      label: 'Top categories',
                      selected: false,
                      onTap: () => _sendQuick(
                        'What are my top spending categories this cycle?',
                        configured,
                        chat.isLoading,
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          // Enter sends; without this a multiline field treats
                          // it as a newline and onSubmitted never fires.
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(configured, chat.isLoading),
                          decoration: InputDecoration(
                            hintText: 'Ask anything…',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton.filled(
                          onPressed: chat.isLoading || !configured
                              ? null
                              : () => _send(configured, chat.isLoading),
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                          ),
                          tooltip: 'Send',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiBanner extends StatelessWidget {
  final String text;

  const _AiBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'Try asking:\n'
        '- How is my current spending pace?\n'
        '- What should I watch this cycle?\n'
        '- Summarize my budget position.',
      ),
    );
  }
}
