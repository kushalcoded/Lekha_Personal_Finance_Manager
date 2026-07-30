import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_expanse_tracker/screens/analytics/models/debt_models.dart';
import 'package:personal_expanse_tracker/screens/analytics/widgets/analytics_section.dart';
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

    final shortHeight = tester.getSize(find.text('Short')).height;
    expect(shortHeight, greaterThan(0));

    final sections = find.byType(AnalyticsSection);
    expect(
      tester.getSize(sections.at(0)).height,
      tester.getSize(sections.at(1)).height,
    );
    expect(tester.getSize(sections.at(0)).height, greaterThan(40));
  });
}
