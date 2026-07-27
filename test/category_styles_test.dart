import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_expanse_tracker/core/constants/category_styles.dart';
import 'package:personal_expanse_tracker/models/category/expense_category.dart';

void main() {
  test('ExpenseCategory JSON round-trips', () {
    const category = ExpenseCategory(
      name: 'Coffee',
      iconKey: 'local_cafe',
      colorHex: '#6E8FA5',
    );
    final restored = ExpenseCategory.fromJson(category.toJson());
    expect(restored.name, 'Coffee');
    expect(restored.iconKey, 'local_cafe');
    expect(restored.colorHex, '#6E8FA5');
  });

  test('parseHex handles valid, prefixed, and invalid input', () {
    expect(CategoryStyles.parseHex('#FF8800'), const Color(0xFFFF8800));
    expect(CategoryStyles.parseHex('FF8800'), const Color(0xFFFF8800));
    // Invalid falls back to the neutral grey rather than throwing.
    expect(CategoryStyles.parseHex('nope'), const Color(0xFF8A8A8A));
  });

  test('iconForKey falls back for unknown keys', () {
    expect(CategoryStyles.iconForKey('restaurant'), Icons.restaurant_rounded);
    expect(CategoryStyles.iconForKey('does_not_exist'), Icons.category_rounded);
  });

  test('applyCustom overlay wins over built-ins and unknowns fall back', () {
    CategoryStyles.applyCustom(const [
      ExpenseCategory(name: 'Food', iconKey: 'local_pizza', colorHex: '#123456'),
    ]);

    // Overlay overrides the built-in Food style.
    final food = CategoryStyles.of('Food');
    expect(food.icon, Icons.local_pizza_rounded);
    expect(food.color, const Color(0xFF123456));

    // A name with no overlay/built-in gets a deterministic palette fallback.
    final unknown = CategoryStyles.of('Zzz Unknown');
    expect(unknown.icon, Icons.category_rounded);
    expect(
      unknown.color,
      CategoryStyles.parseHex(CategoryStyles.fallbackHexFor('Zzz Unknown')),
    );

    CategoryStyles.applyCustom(const []); // reset overlay for other tests
  });

  test('default seed includes the protected catch-all category', () {
    expect(
      defaultExpenseCategories.any((c) => c.name == kProtectedCategoryName),
      isTrue,
    );
  });
}
