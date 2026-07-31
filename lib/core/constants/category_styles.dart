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

  /// Midnight Terminal category tint family (mockup: amber/teal/sky/tan/
  /// purple…) — consistent saturation and lightness so every hue sits calmly
  /// on the dark ground. Used for the color picker and deterministic
  /// fallbacks. Violet is deliberately absent: violet means tappable.
  static const List<String> paletteHex = [
    '#F0A13B', // amber
    '#E8906A', // coral
    '#D8A878', // sand
    '#C7B08A', // tan
    '#A3BF7B', // sage
    '#7BC98F', // green
    '#5AB5A5', // teal
    '#6BC0CE', // cyan
    '#64B5E8', // sky
    '#8FA3BF', // slate blue
    '#8F9FE0', // periwinkle
    '#C08AD8', // purple
    '#CE93C4', // orchid
    '#D98BB0', // pink
    '#E8879C', // rose
    '#9AA1AD', // neutral slate
  ];

  /// Old muted palette → its Midnight Terminal replacement. Custom
  /// categories saved before the redesign carry these hexes in Hive; the
  /// remap converts them at render time without rewriting storage.
  static const Map<String, String> _legacyHex = {
    '#6E8FA5': '#64B5E8',
    '#7C6FAF': '#8F9FE0',
    '#6EA39B': '#5AB5A5',
    '#8A9B6E': '#7BC98F',
    '#9B7C7C': '#E8879C',
    '#6E7F9C': '#8FA3BF',
    '#9C7E6E': '#E8906A',
    '#7E9C85': '#A3BF7B',
    '#7A9C8B': '#6BC0CE',
    '#8E8A6D': '#A3BF7B',
    '#B18AA8': '#CE93C4',
    '#7FA8A8': '#5AB5A5',
    '#8A7C9A': '#C08AD8',
    '#6D8AAE': '#64B5E8',
    '#B07A7A': '#D98BB0',
    '#9A8C6E': '#C7B08A',
    '#8A8A8A': '#9AA1AD',
  };

  /// Built-in styles, on the Midnight Terminal tint family (Food amber,
  /// Shopping teal, Transport sky, Utilities tan — straight from the mockup).
  static const Map<String, CategoryStyle> _styles = {
    'Food': CategoryStyle(
      icon: Icons.restaurant_rounded,
      color: Color(0xFFF0A13B),
    ),
    'Fuel': CategoryStyle(
      icon: Icons.local_gas_station_rounded,
      color: Color(0xFFE8906A),
    ),
    'Shopping': CategoryStyle(
      icon: Icons.shopping_bag_rounded,
      color: Color(0xFF5AB5A5),
    ),
    'Friends': CategoryStyle(
      icon: Icons.people_alt_rounded,
      color: Color(0xFF7BC98F),
    ),
    'Subscriptions': CategoryStyle(
      icon: Icons.subscriptions_rounded,
      color: Color(0xFF8F9FE0),
    ),
    'Travel': CategoryStyle(
      icon: Icons.flight_rounded,
      color: Color(0xFF6BC0CE),
    ),
    'Health': CategoryStyle(
      icon: Icons.local_hospital_rounded,
      color: Color(0xFFE8879C),
    ),
    'Bills': CategoryStyle(
      icon: Icons.receipt_long_rounded,
      color: Color(0xFF8FA3BF),
    ),
    'Entertainment': CategoryStyle(
      icon: Icons.movie_rounded,
      color: Color(0xFFC08AD8),
    ),
    'Investment': CategoryStyle(
      icon: Icons.trending_up_rounded,
      color: Color(0xFFA3BF7B),
    ),
    'Luxury': CategoryStyle(
      icon: Icons.diamond_rounded,
      color: Color(0xFFCE93C4),
    ),
    'Miscellaneous': CategoryStyle(
      icon: Icons.category_rounded,
      color: Color(0xFF9AA1AD),
    ),
    'Rent': CategoryStyle(icon: Icons.home_rounded, color: Color(0xFFD8A878)),
    'Gifts': CategoryStyle(
      icon: Icons.card_giftcard_rounded,
      color: Color(0xFFD98BB0),
    ),
    'Transport': CategoryStyle(
      icon: Icons.directions_car_rounded,
      color: Color(0xFF64B5E8),
    ),
    'Utilities': CategoryStyle(
      icon: Icons.lightbulb_rounded,
      color: Color(0xFFC7B08A),
    ),
    'Healthcare': CategoryStyle(
      icon: Icons.favorite_rounded,
      color: Color(0xFFE8879C),
    ),
    'Other': CategoryStyle(
      icon: Icons.category_rounded,
      color: Color(0xFF9AA1AD),
    ),
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
            CategoryStyle(
              icon: iconForKey(c.iconKey),
              color: parseHex(c.colorHex),
            ),
          ),
        ),
      );
  }

  static IconData iconForKey(String key) {
    return iconOptions[key] ?? Icons.category_rounded;
  }

  static Color parseHex(String hex) {
    final normalized = '#${hex.trim().replaceAll('#', '').toUpperCase()}';
    var value = (_legacyHex[normalized] ?? normalized).replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? const Color(0xFF9AA1AD) : Color(parsed);
  }

  /// Stable palette color for a name when no explicit style exists.
  static String fallbackHexFor(String name) {
    if (name.isEmpty) return '#9AA1AD';
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
