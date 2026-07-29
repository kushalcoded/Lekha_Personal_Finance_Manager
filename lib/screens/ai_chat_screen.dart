import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ai_providers.dart';
import '../widgets/common/ai_text.dart';
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

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(aiChatProvider);
    final configured = ref.watch(geminiConfiguredProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        actions: [
          IconButton(
            onPressed: () => ref.read(aiChatProvider.notifier).clear(),
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear chat',
          ),
        ],
      ),
      body: Column(
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
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.16)
                              : Theme.of(context).colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.55),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isUser ? 16 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 16),
                          ),
                          border: Border.all(
                            color: isUser
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.28)
                                : Colors.white.withValues(alpha: 0.08),
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
                radius: 14,
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
                      onPressed: () =>
                          ref.read(aiChatProvider.notifier).confirmPending(),
                      child: const Text('Confirm'),
                    ),
                  ],
                ),
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
                      decoration: const InputDecoration(
                        hintText: 'Ask about your spending, budget, or history',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: chat.isLoading || !configured
                        ? null
                        : () async {
                            final text = _controller.text;
                            _controller.clear();
                            await ref.read(aiChatProvider.notifier).send(text);
                          },
                    child: const Text('Send'),
                  ),
                ],
              ),
            ),
          ),
        ],
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
