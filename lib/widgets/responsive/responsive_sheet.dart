import 'package:flutter/material.dart';

/// Shows [desktopChild] in a centered dialog on wide screens (>=900px) and
/// [mobileChild] in a bottom sheet otherwise.
Future<void> showResponsiveSheet(
  BuildContext context, {
  required Widget mobileChild,
  required Widget desktopChild,
  double maxWidth = 560,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final isDesktop = MediaQuery.of(context).size.width >= 900;

  if (isDesktop) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: desktopChild,
        ),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(top: false, child: mobileChild),
    ),
  );
}
