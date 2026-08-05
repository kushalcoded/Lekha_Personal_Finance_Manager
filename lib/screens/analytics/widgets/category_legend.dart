import 'package:flutter/material.dart';

import '../../../core/constants/category_styles.dart';
import '../../../utils/formatters/formatters.dart';
import '../models/analytics_models.dart';

class CategoryLegend extends StatefulWidget {
  final List<CategoryStat> items;

  /// Fixed height that turns the list into its own scroll area, for the
  /// desktop layout where the legend sits beside the donut and can't be
  /// allowed to stretch the card. Null lets it grow to fit — on mobile the
  /// page already scrolls, and a scroll view inside one just fights the gesture.
  ///
  /// It must be a TIGHT height, not a max: this card renders inside
  /// [IntrinsicHeight], which asks its children how tall they want to be, and
  /// a scroll view can't answer that. A tight SizedBox replies with its own
  /// number instead of forwarding the question.
  final double? height;

  const CategoryLegend({super.key, required this.items, this.height});

  @override
  State<CategoryLegend> createState() => _CategoryLegendState();
}

class _CategoryLegendState extends State<CategoryLegend> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = Column(
      mainAxisSize: MainAxisSize.min,
      children: widget.items.map(_row).toList(),
    );

    if (widget.height == null) return rows;

    return SizedBox(
      height: widget.height,
      child: Scrollbar(
        controller: _controller,
        // Always visible: the whole point is telling the user more categories
        // exist below the fold.
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _controller,
          // Room for the scrollbar so it never sits on top of the percentages.
          padding: const EdgeInsets.only(right: 12),
          child: rows,
        ),
      ),
    );
  }

  Widget _row(CategoryStat stat) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = CategoryStyles.of(stat.category);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: style.tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(style.icon, size: 16, color: style.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppFormatters.formatCurrency(stat.amount),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: style.chipTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${stat.percent.toStringAsFixed(0)}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: style.color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
