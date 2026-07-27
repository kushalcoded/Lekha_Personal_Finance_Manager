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
      colorHex: json['colorHex'] as String? ?? '#8A8A8A',
    );
  }
}

/// Catch-all category that cannot be renamed or deleted, and receives any
/// expenses left orphaned when another category is deleted. Matches the
/// existing default for [Payable.category].
const kProtectedCategoryName = 'Miscellaneous';

/// Seeded on first run so the app starts with the same categories as before.
const defaultExpenseCategories = <ExpenseCategory>[
  ExpenseCategory(name: 'Food', iconKey: 'restaurant', colorHex: '#6E8FA5'),
  ExpenseCategory(name: 'Friends', iconKey: 'people', colorHex: '#8A9B6E'),
  ExpenseCategory(
    name: 'Fuel',
    iconKey: 'local_gas_station',
    colorHex: '#7C6FAF',
  ),
  ExpenseCategory(
    name: 'Shopping',
    iconKey: 'shopping_bag',
    colorHex: '#6EA39B',
  ),
  ExpenseCategory(name: 'Luxury', iconKey: 'diamond', colorHex: '#B18AA8'),
  ExpenseCategory(name: 'Rent', iconKey: 'home', colorHex: '#7FA8A8'),
  ExpenseCategory(name: 'Bills', iconKey: 'receipt_long', colorHex: '#7E9C85'),
  ExpenseCategory(
    name: 'Subscriptions',
    iconKey: 'subscriptions',
    colorHex: '#9B7C7C',
  ),
  ExpenseCategory(name: 'Travel', iconKey: 'flight', colorHex: '#6E7F9C'),
  ExpenseCategory(
    name: 'Health',
    iconKey: 'local_hospital',
    colorHex: '#9C7E6E',
  ),
  ExpenseCategory(name: 'Gifts', iconKey: 'card_giftcard', colorHex: '#8A7C9A'),
  ExpenseCategory(
    name: 'Entertainment',
    iconKey: 'movie',
    colorHex: '#7A9C8B',
  ),
  ExpenseCategory(
    name: 'Investment',
    iconKey: 'trending_up',
    colorHex: '#8E8A6D',
  ),
  ExpenseCategory(
    name: kProtectedCategoryName,
    iconKey: 'category',
    colorHex: '#8A8A8A',
  ),
];
