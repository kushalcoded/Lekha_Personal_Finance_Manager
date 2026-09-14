import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/ai/dashboard_insight.dart';

/// The Home summary card lays out whatever the model sends. A reply it cannot
/// read must still give the card something to show, never an empty box.
void main() {
  test('reads tone, text and where each point leads', () {
    final items = parseDashboardInsights(
      '```json\n{"items":[{"tone":"alert","text":"**3** debts overdue",'
      '"target":"debts"},{"tone":"good","text":"On track","target":null}]}\n```',
    );
    expect(items.map((i) => i.tone), [InsightTone.alert, InsightTone.good]);
    expect(items.first.target, InsightTarget.debts);
    expect(items.last.target, isNull);
  });

  test('anything unexpected falls back to a neutral point', () {
    final items = parseDashboardInsights(
      '{"items":[{"tone":"urgent","text":"Hi","target":"budget"},{"text":""}]}',
    );
    expect(items.single.tone, InsightTone.info);
    expect(items.single.target, isNull);
  });

  test('plain lines still become points, without their bullets', () {
    final items = parseDashboardInsights(
      '- Settle 3 overdue debts\n2. Budget has ₹7,133 left\n\n• Keep going',
    );
    expect(items.map((i) => i.text), [
      'Settle 3 overdue debts',
      'Budget has ₹7,133 left',
      'Keep going',
    ]);
  });

  test('never more than three', () {
    final items = parseDashboardInsights('a\nb\nc\nd\ne');
    expect(items, hasLength(3));
  });
}
