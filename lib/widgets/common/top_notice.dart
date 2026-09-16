import 'dart:async';

import 'package:flutter/material.dart';

import '../../main.dart' show navigatorKey;

/// A short message at the top of the screen — "Expense saved", "Synced".
///
/// Replaces SnackBars, which Flutter can only place at the bottom, where they
/// sat over the + button for their whole three seconds. Drawn on the root
/// navigator's overlay, so callers need no BuildContext and nothing breaks
/// when the sheet that asked for it has already closed.
void showNotice(
  String message, {
  String? actionLabel,
  VoidCallback? onAction,

  /// For "working on it" messages that the result will replace.
  Duration? duration,
}) {
  final overlay = navigatorKey.currentState?.overlay;
  if (overlay == null) return;

  // One at a time: a new message replaces the current one outright.
  final previous = _current;
  if (previous != null) _remove(previous);

  final key = GlobalKey<_NoticeState>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Notice(
      key: key,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              hideNotice();
              onAction();
            },
      // Bound to this entry: a notice that finishes sliding away after it was
      // replaced must not take its replacement down with it.
      onGone: () => _remove(entry),
    ),
  );
  _current = entry;
  _currentKey = key;
  overlay.insert(entry);
  _inOverlay.add(entry);
  _timer = Timer(
    // Long enough to reach an Undo.
    duration ?? Duration(seconds: actionLabel == null ? 3 : 5),
    hideNotice,
  );
}

/// Slide the current notice away, if there is one.
void hideNotice() {
  _timer?.cancel();
  final entry = _current;
  if (entry == null) return;
  final state = _currentKey?.currentState;
  if (state == null) {
    _remove(entry);
  } else {
    state.dismiss();
  }
}

OverlayEntry? _current;
GlobalKey<_NoticeState>? _currentKey;
Timer? _timer;

/// Entries this file has inserted and not yet taken out.
///
/// Not [OverlayEntry.mounted]: an entry only counts as mounted once a frame
/// has built it. Saving a detected payment posts two notices back to back —
/// the caller's, then the sheet's — so the second one arrived while the first
/// was inserted but not yet built, the mounted check skipped it, and it was
/// built a frame later with nothing left that would ever remove it. It then
/// stayed on screen across every tab. Being in the overlay is the fact that
/// matters, so that is what is tracked.
final Set<OverlayEntry> _inOverlay = {};

void _remove(OverlayEntry entry) {
  if (identical(_current, entry)) {
    _timer?.cancel();
    _current = null;
    _currentKey = null;
  }
  if (_inOverlay.remove(entry)) entry.remove();
}

class _Notice extends StatefulWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onGone;

  const _Notice({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onGone,
  });

  @override
  State<_Notice> createState() => _NoticeState();
}

class _NoticeState extends State<_Notice> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 140),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  Future<void> dismiss() async {
    if (!mounted || MediaQuery.of(context).disableAnimations) {
      widget.onGone();
      return;
    }
    // Going away should not depend on an animation finishing: tickers pause
    // while the app is in the background, which would hold a timed-out notice
    // on screen until the next frame. (This is not what stranded notices for
    // good — that was the mounted check in _remove; see _inOverlay.)
    await Future.any([
      _controller.reverse(),
      Future<void>.delayed(const Duration(milliseconds: 400)),
    ]);
    widget.onGone();
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
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, -0.6),
                    end: Offset.zero,
                  ).animate(curved),
                  child: GestureDetector(
                    // Flick it back up to dismiss early.
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) < -150) hideNotice();
                    },
                    child: Semantics(
                      liveRegion: true,
                      child: Material(
                        color: cs.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: cs.outline),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            widget.actionLabel == null ? 13 : 4,
                            widget.actionLabel == null ? 16 : 6,
                            widget.actionLabel == null ? 13 : 4,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.message,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              if (widget.actionLabel != null)
                                TextButton(
                                  onPressed: widget.onAction,
                                  child: Text(widget.actionLabel!),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
