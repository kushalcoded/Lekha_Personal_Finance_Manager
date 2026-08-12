import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/providers/categories/category_providers.dart';

/// Detects categories the settings-wipe bug deleted: names records still carry
/// that are no longer in the category list.
///
/// This is only meaningful because deleting a category migrates its records to
/// Miscellaneous first — so a surviving orphan name cannot come from an
/// intentional delete, only from the list vanishing underneath the records.
void main() {
  const configured = ['Food', 'Travel', 'Miscellaneous'];

  test('a name records use but the list lost is reported', () {
    expect(
      missingCategoryNames(configured, ['Food', 'Transport', 'Rakhi']),
      ['Rakhi', 'Transport'],
    );
  });

  test('nothing is reported when every name is configured', () {
    expect(missingCategoryNames(configured, ['Food', 'Travel']), isEmpty);
  });

  test('matching ignores case, so a differently-typed name is not "missing"', () {
    expect(missingCategoryNames(configured, ['food', 'TRAVEL']), isEmpty);
  });

  test('the first spelling seen is the one offered', () {
    // Restoring should use what the records look like, not a lowercased key.
    expect(missingCategoryNames(configured, ['Transport', 'transport']), [
      'Transport',
    ]);
  });

  test('blank and whitespace names are ignored', () {
    expect(missingCategoryNames(configured, ['', '   ', 'Food']), isEmpty);
  });

  test('output is sorted, so the banner does not reshuffle', () {
    final names = missingCategoryNames(configured, [
      'Zoo',
      'apple',
      'Mango',
    ]);
    expect(names, ['apple', 'Mango', 'Zoo']);
  });

  test('no records means nothing to restore', () {
    expect(missingCategoryNames(configured, const []), isEmpty);
  });

  test('an empty category list reports everything in use', () {
    // The worst case of the bug: the list was wiped entirely.
    expect(missingCategoryNames(const [], ['Food', 'Travel']), [
      'Food',
      'Travel',
    ]);
  });
}
