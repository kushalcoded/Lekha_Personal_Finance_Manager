import 'package:flutter/material.dart';

import '../../models/category/expense_category.dart';

class CategoryStyle {
  final IconData icon;
  final Color color;

  const CategoryStyle({required this.icon, required this.color});

  Color get tint => color.withValues(alpha: 0.12);
  Color get chipTint => color.withValues(alpha: 0.18);
}

class CategoryStyles {
  /// Curated Material icon allowlist. Custom categories (and Gemini's icon
  /// suggestions) may only reference these keys, which keeps every icon
  /// statically referenced and therefore tree-shake safe (no APK bloat).
  static const Map<String, IconData> iconOptions = {
    'restaurant': Icons.restaurant_rounded,
    'fastfood': Icons.fastfood_rounded,
    'local_pizza': Icons.local_pizza_rounded,
    'local_cafe': Icons.local_cafe_rounded,
    'local_bar': Icons.local_bar_rounded,
    'local_grocery_store': Icons.local_grocery_store_rounded,
    'local_gas_station': Icons.local_gas_station_rounded,
    'shopping_bag': Icons.shopping_bag_rounded,
    'shopping_cart': Icons.shopping_cart_rounded,
    'checkroom': Icons.checkroom_rounded,
    'people': Icons.people_alt_rounded,
    'diamond': Icons.diamond_rounded,
    'home': Icons.home_rounded,
    'receipt_long': Icons.receipt_long_rounded,
    'subscriptions': Icons.subscriptions_rounded,
    'flight': Icons.flight_rounded,
    'hotel': Icons.hotel_rounded,
    'beach_access': Icons.beach_access_rounded,
    'local_hospital': Icons.local_hospital_rounded,
    'medical_services': Icons.medical_services_rounded,
    'local_pharmacy': Icons.local_pharmacy_rounded,
    'favorite': Icons.favorite_rounded,
    'fitness_center': Icons.fitness_center_rounded,
    'spa': Icons.spa_rounded,
    'card_giftcard': Icons.card_giftcard_rounded,
    'celebration': Icons.celebration_rounded,
    'cake': Icons.cake_rounded,
    'movie': Icons.movie_rounded,
    'music_note': Icons.music_note_rounded,
    'sports_esports': Icons.sports_esports_rounded,
    'trending_up': Icons.trending_up_rounded,
    'savings': Icons.savings_rounded,
    'account_balance': Icons.account_balance_rounded,
    'credit_card': Icons.credit_card_rounded,
    'directions_car': Icons.directions_car_rounded,
    'directions_bus': Icons.directions_bus_rounded,
    'train': Icons.train_rounded,
    'two_wheeler': Icons.two_wheeler_rounded,
    'local_taxi': Icons.local_taxi_rounded,
    'lightbulb': Icons.lightbulb_rounded,
    'bolt': Icons.bolt_rounded,
    'water_drop': Icons.water_drop_rounded,
    'wifi': Icons.wifi_rounded,
    'phone_android': Icons.phone_android_rounded,
    'school': Icons.school_rounded,
    'book': Icons.menu_book_rounded,
    'pets': Icons.pets_rounded,
    'child_care': Icons.child_care_rounded,
    'build': Icons.build_rounded,
    'cleaning_services': Icons.cleaning_services_rounded,
    'park': Icons.park_rounded,
    'category': Icons.category_rounded,
  };

  /// Muted palette used for the color picker and deterministic fallbacks.
  static const List<String> paletteHex = [
    '#6E8FA5',
    '#7C6FAF',
    '#6EA39B',
    '#8A9B6E',
    '#9B7C7C',
    '#6E7F9C',
    '#9C7E6E',
    '#7E9C85',
    '#7A9C8B',
    '#8E8A6D',
    '#B18AA8',
    '#7FA8A8',
    '#8A7C9A',
    '#6D8AAE',
    '#B07A7A',
    '#8A8A8A',
  ];

  /// Built-in fallback styles for any legacy category names.
  static const Map<String, CategoryStyle> _styles = {
    'Food': CategoryStyle(icon: Icons.restaurant_rounded, color: Color(0xFF6E8FA5)),
    'Fuel': CategoryStyle(icon: Icons.local_gas_station_rounded, color: Color(0xFF7C6FAF)),
    'Shopping': CategoryStyle(icon: Icons.shopping_bag_rounded, color: Color(0xFF6EA39B)),
    'Friends': CategoryStyle(icon: Icons.people_alt_rounded, color: Color(0xFF8A9B6E)),
    'Subscriptions': CategoryStyle(icon: Icons.subscriptions_rounded, color: Color(0xFF9B7C7C)),
    'Travel': CategoryStyle(icon: Icons.flight_rounded, color: Color(0xFF6E7F9C)),
    'Health': CategoryStyle(icon: Icons.local_hospital_rounded, color: Color(0xFF9C7E6E)),
    'Bills': CategoryStyle(icon: Icons.receipt_long_rounded, color: Color(0xFF7E9C85)),
    'Entertainment': CategoryStyle(icon: Icons.movie_rounded, color: Color(0xFF7A9C8B)),
    'Investment': CategoryStyle(icon: Icons.trending_up_rounded, color: Color(0xFF8E8A6D)),
    'Luxury': CategoryStyle(icon: Icons.diamond_rounded, color: Color(0xFFB18AA8)),
    'Miscellaneous': CategoryStyle(icon: Icons.category_rounded, color: Color(0xFF8A8A8A)),
    'Rent': CategoryStyle(icon: Icons.home_rounded, color: Color(0xFF7FA8A8)),
    'Gifts': CategoryStyle(icon: Icons.card_giftcard_rounded, color: Color(0xFF8A7C9A)),
    'Transport': CategoryStyle(icon: Icons.directions_car_rounded, color: Color(0xFF6D8AAE)),
    'Utilities': CategoryStyle(icon: Icons.lightbulb_rounded, color: Color(0xFF9A8C6E)),
    'Healthcare': CategoryStyle(icon: Icons.favorite_rounded, color: Color(0xFFB07A7A)),
    'Other': CategoryStyle(icon: Icons.category_rounded, color: Color(0xFF8A8A8A)),
  };

  /// Runtime overlay populated from the user's custom categories. Checked
  /// before the built-in map so every render site (dashboard, analytics,
  /// expense list, etc.) reflects edits without any changes to those widgets.
  // ponytail: global static overlay, fine for this single-user app; move to a
  // provider-scoped map if multi-user styling is ever needed.
  static final Map<String, CategoryStyle> _overlay = {};

  /// Rebuild the overlay from the current custom category list.
  static void applyCustom(List<ExpenseCategory> categories) {
    _overlay
      ..clear()
      ..addEntries(
        categories.map(
          (c) => MapEntry(
            c.name,
            CategoryStyle(icon: iconForKey(c.iconKey), color: parseHex(c.colorHex)),
          ),
        ),
      );
  }

  static IconData iconForKey(String key) {
    return iconOptions[key] ?? Icons.category_rounded;
  }

  static Color parseHex(String hex) {
    var value = hex.trim().replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? const Color(0xFF8A8A8A) : Color(parsed);
  }

  /// Stable palette color for a name when no explicit style exists.
  static String fallbackHexFor(String name) {
    if (name.isEmpty) return '#8A8A8A';
    return paletteHex[name.hashCode.abs() % paletteHex.length];
  }

  static CategoryStyle of(String category) {
    final overlay = _overlay[category];
    if (overlay != null) return overlay;
    final builtin = _styles[category];
    if (builtin != null) return builtin;
    return CategoryStyle(
      icon: Icons.category_rounded,
      color: parseHex(fallbackHexFor(category)),
    );
  }
}
