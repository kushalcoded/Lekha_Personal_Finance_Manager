import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/form_bits.dart';
import '../../../widgets/responsive/responsive_sheet.dart';
import '../providers/recurring_expenses_providers.dart' show shiftByMonths;
import 'save_expense_button.dart';

const _maxMonths = 60;

/// Choose how many months Insights spreads a payment over. Returns the choice,
/// or null if the sheet was dismissed; 1 means "don't spread".
Future<int?> showSpreadSheet(
  BuildContext context, {
  required double amount,
  required DateTime date,
  required int months,
}) {
  final sheet = _SpreadSheet(amount: amount, date: date, initial: months);
  return showResponsiveSheet<int>(
    context,
    maxWidth: 420,
    mobileChild: sheet,
    desktopChild: sheet,
  );
}

/// How a spread reads back on a tile or a detail row.
String spreadLabel(int months) => months <= 1 ? 'Once' : '$months months';

class _SpreadSheet extends StatefulWidget {
  final double amount;
  final DateTime date;
  final int initial;

  const _SpreadSheet({
    required this.amount,
    required this.date,
    required this.initial,
  });

  @override
  State<_SpreadSheet> createState() => _SpreadSheetState();
}

class _SpreadSheetState extends State<_SpreadSheet> {
  late int _months = widget.initial.clamp(1, _maxMonths);

  void _set(int months) =>
      setState(() => _months = months.clamp(1, _maxMonths));

  /// Said in money and dates, because "spread over 12 months" on its own does
  /// not tell you what Insights will actually draw.
  String _outcome() {
    if (_months <= 1) return 'Counted once, in the month you paid.';
    final month = DateFormat('MMM yyyy');
    final last = shiftByMonths(widget.date, _months - 1);
    final share = widget.amount / _months;
    return '${AppFormatters.formatCurrency(share)} a month · '
        '${month.format(widget.date)} → ${month.format(last)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spread over',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${AppFormatters.formatCurrency(widget.amount)} paid on '
            '${DateFormat('d MMM yyyy').format(widget.date)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepButton(
                icon: Icons.remove_rounded,
                label: 'One month fewer',
                onPressed: _months > 1 ? () => _set(_months - 1) : null,
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 96,
                child: Column(
                  children: [
                    Text(
                      '$_months',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontFamily: 'Space Grotesk',
                        fontWeight: FontWeight.w700,
                        fontSize: 36,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      _months == 1 ? 'month' : 'months',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _StepButton(
                icon: Icons.add_rounded,
                label: 'One month more',
                onPressed: _months < _maxMonths
                    ? () => _set(_months + 1)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // The common lengths one tap away; the stepper is for everything
          // in between.
          SizedBox(
            // Full width, or the Wrap shrink-wraps inside this start-aligned
            // Column and the pills sit left instead of centred.
            width: double.infinity,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final preset in const [1, 3, 6, 12, 24])
                  ChoicePill(
                    label: preset == 1 ? 'Once' : '$preset mo',
                    selected: _months == preset,
                    onTap: () => _set(preset),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _outcome(),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Only changes how Insights draws it. Home and your budget still '
            'count the full amount in the month you paid.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          SaveExpenseButton(
            label: _months <= 1
                ? "Don't spread"
                : 'Spread over $_months months',
            isEnabled: true,
            onPressed: () => Navigator.of(context).pop(_months),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _StepButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton.outlined(
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon),
      // 48 keeps it comfortably above the 44 minimum a thumb needs.
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      style: IconButton.styleFrom(
        side: BorderSide(color: cs.outline.withValues(alpha: 0.4)),
      ),
    );
  }
}
