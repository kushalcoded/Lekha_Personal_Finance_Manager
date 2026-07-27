import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/screens/expenses/utils/split_helpers.dart';

void main() {
  group('equal split', () {
    test('₹1200 three ways gives everyone ₹400', () {
      final r = computeSplit(total: 1200, people: ['Rahul', 'Amit']);
      expect(r.myShare, 400);
      expect(r.others.map((s) => s.amount), [400, 400]);
      expect(r.myShare + r.othersTotal, 1200);
    });

    test('rounding remainder lands on you and still sums to the total', () {
      final r = computeSplit(total: 1000, people: ['Rahul', 'Amit']);
      expect(r.others.map((s) => s.amount), [333.33, 333.33]);
      expect(r.myShare, 333.34);
      expect(r.myShare + r.othersTotal, closeTo(1000, 0.001));
    });

    test('no people means the whole bill is yours', () {
      final r = computeSplit(total: 500, people: []);
      expect(r.myShare, 500);
      expect(r.others, isEmpty);
    });
  });

  group('exact split', () {
    test('your share is whatever is left over', () {
      final r = computeSplit(
        total: 1200,
        people: ['Rahul', 'Amit'],
        mode: SplitMode.exact,
        exactAmounts: {'Rahul': 500, 'Amit': 300},
      );
      expect(r.othersTotal, 800);
      expect(r.myShare, 400);
    });
  });

  group('validation', () {
    test('rejects shares exceeding the total', () {
      final r = computeSplit(
        total: 500,
        people: ['Rahul'],
        mode: SplitMode.exact,
        exactAmounts: {'Rahul': 900},
      );
      expect(validateSplit(500, r), isNotNull);
    });

    test('accepts a sane split', () {
      final r = computeSplit(total: 1200, people: ['Rahul', 'Amit']);
      expect(validateSplit(1200, r), isNull);
    });

    test('rejects a zero total', () {
      final r = computeSplit(total: 0, people: ['Rahul']);
      expect(validateSplit(0, r), isNotNull);
    });
  });
}
