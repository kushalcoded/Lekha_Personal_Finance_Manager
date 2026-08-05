import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_expanse_tracker/screens/analytics/models/analytics_models.dart';
import 'package:personal_expanse_tracker/screens/analytics/models/debt_models.dart';
import 'package:personal_expanse_tracker/screens/analytics/widgets/analytics_section.dart';
import 'package:personal_expanse_tracker/screens/analytics/widgets/category_legend.dart';
import 'package:personal_expanse_tracker/screens/analytics/widgets/debt_overview_panel.dart';

void main() {
  // Regression: the desktop two-up rows wrap sections in IntrinsicHeight.
  // A LayoutBuilder anywhere in that subtree reports zero intrinsic height
  // in release builds (throws here in test mode), collapsing every row.
  testWidgets('paired sections survive IntrinsicHeight and match heights', (
    tester,
  ) async {
    const summary = DebtSummary(
      totalReceivables: 100,
      totalPayables: 50,
      netBalance: 50,
      overdueReceivables: 0,
      overduePayables: 0,
      settledAmount: 20,
      activeDebtors: 1,
      activeCreditors: 1,
    );
    const overdue = DebtOverdueStats(
      overdueReceivablesTotal: 0,
      overduePayablesTotal: 0,
      overdueReceivablesCount: 0,
      overduePayablesCount: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                Expanded(
                  child: AnalyticsSection(
                    stretch: true,
                    title: 'Short',
                    child: SizedBox(height: 40),
                  ),
                ),
                Expanded(
                  child: AnalyticsSection(
                    stretch: true,
                    title: 'Tall',
                    child: DebtOverviewPanel(
                      summary: summary,
                      overdueStats: overdue,
                      topDebtors: [],
                      topCreditors: [],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Section titles render as mono uppercase.
    final shortHeight = tester.getSize(find.text('SHORT')).height;
    expect(shortHeight, greaterThan(0));

    final sections = find.byType(AnalyticsSection);
    expect(
      tester.getSize(sections.at(0)).height,
      tester.getSize(sections.at(1)).height,
    );
    expect(tester.getSize(sections.at(0)).height, greaterThan(40));
  });

  // The legend scrolls so every category is reachable, but it renders inside
  // the same IntrinsicHeight row. A scroll view can't report an intrinsic
  // height, so only a TIGHT SizedBox keeps this from throwing — a
  // ConstrainedBox(maxHeight:) forwards the question to the viewport and dies.
  testWidgets('the scrolling category legend survives IntrinsicHeight', (
    tester,
  ) async {
    final stats = List.generate(
      12,
      (i) => CategoryStat(
        category: 'Category $i',
        amount: 100.0 * (12 - i),
        percent: 8,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: CategoryLegend(items: stats, height: 340)),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(CategoryLegend)).height, 340);
    // Every category is built, including ones below the fold — the legend used
    // to silently drop everything after the sixth.
    expect(find.text('Category 11', skipOffstage: false), findsOneWidget);
  });

  testWidgets('without a height the legend grows for the page to scroll', (
    tester,
  ) async {
    final stats = List.generate(
      12,
      (i) => CategoryStat(category: 'Category $i', amount: 100, percent: 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: CategoryLegend(items: stats)),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // Taller than any fixed pane: nothing is clipped away on mobile.
    expect(
      tester.getSize(find.byType(CategoryLegend)).height,
      greaterThan(340),
    );
  });
}
