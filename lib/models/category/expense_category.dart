/// A user-customizable expense category: a name plus its visual style
/// (an icon key from [CategoryStyles.iconOptions] and a hex color).
class ExpenseCategory {
  final String name;
  final String iconKey;
  final String colorHex; // #RRGGBB

  const ExpenseCategory({
    required this.name,
    required this.iconKey,
    required this.colorHex,
  });

  ExpenseCategory copyWith({String? name, String? iconKey, String? colorHex}) {
    return ExpenseCategory(
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      colorHex: colorHex ?? this.colorHex,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'iconKey': iconKey, 'colorHex': colorHex};
  }

  factory ExpenseCategory.fromJson(Map<dynamic, dynamic> json) {
    return ExpenseCategory(
      name: json['name'] as String,
      iconKey: json['iconKey'] as String? ?? 'category',
      colorHex: json['colorHex'] as String? ?? '#9AA1AD',
    );
  }
}

/// Catch-all category that cannot be renamed or deleted, and receives any
/// expenses left orphaned when another category is deleted. Matches the
/// existing default for [Payable.category].
const kProtectedCategoryName = 'Miscellaneous';

/// Seeded on first run — colors from the Midnight Terminal tint family
/// (CategoryStyles.paletteHex). Pre-redesign hexes already stored in Hive
/// are remapped at render time by CategoryStyles.parseHex.
const defaultExpenseCategories = <ExpenseCategory>[
  ExpenseCategory(name: 'Food', iconKey: 'restaurant', colorHex: '#F0A13B'),
  ExpenseCategory(name: 'Friends', iconKey: 'people', colorHex: '#7BC98F'),
  ExpenseCategory(
    name: 'Fuel',
    iconKey: 'local_gas_station',
    colorHex: '#E8906A',
  ),
  ExpenseCategory(
    name: 'Shopping',
    iconKey: 'shopping_bag',
    colorHex: '#5AB5A5',
  ),
  ExpenseCategory(name: 'Luxury', iconKey: 'diamond', colorHex: '#CE93C4'),
  ExpenseCategory(name: 'Rent', iconKey: 'home', colorHex: '#D8A878'),
  ExpenseCategory(name: 'Bills', iconKey: 'receipt_long', colorHex: '#8FA3BF'),
  ExpenseCategory(
    name: 'Subscriptions',
    iconKey: 'subscriptions',
    colorHex: '#8F9FE0',
  ),
  ExpenseCategory(name: 'Travel', iconKey: 'flight', colorHex: '#6BC0CE'),
  ExpenseCategory(
    name: 'Health',
    iconKey: 'local_hospital',
    colorHex: '#E8879C',
  ),
  ExpenseCategory(name: 'Gifts', iconKey: 'card_giftcard', colorHex: '#D98BB0'),
  ExpenseCategory(name: 'Entertainment', iconKey: 'movie', colorHex: '#C08AD8'),
  ExpenseCategory(
    name: 'Investment',
    iconKey: 'trending_up',
    colorHex: '#A3BF7B',
  ),
  ExpenseCategory(
    name: kProtectedCategoryName,
    iconKey: 'category',
    colorHex: '#9AA1AD',
  ),
];
