/// What a category's money *means*, and so whether it counts as spending.
///
/// This lives on the category rather than on each expense for two reasons:
/// categories already ride the per-user settings map, so it syncs, merges and
/// backs up with no new plumbing; and it is one decision per category instead
/// of one per transaction.
enum CategoryKind {
  /// Food, shopping — the part of spending you choose week to week.
  everyday,

  /// Rent, bills, EMIs. Real spending, but not a choice, so it is reserved
  /// apart from everyday money instead of competing with it.
  committed,

  /// SIPs and the like. It left the account, but you still own it.
  investment,

  /// Moving your own money: a credit-card bill, a wallet top-up, cash out of
  /// an ATM. What it pays for is counted on its own, so counting this too
  /// would count it twice.
  transfer,

  /// Money coming in — salary, a bonus, cashback, a reimbursement.
  income,
}

extension CategoryKindX on CategoryKind {
  /// Everyday and committed are money consumed; everything else merely moved.
  /// Nearly every total in the app wants exactly this distinction.
  bool get countsAsSpent =>
      this == CategoryKind.everyday || this == CategoryKind.committed;

  /// How the kind is written on a row or a picker. Everyday is the norm and
  /// says nothing.
  String? get tag => switch (this) {
    CategoryKind.everyday => null,
    CategoryKind.committed => 'BILL',
    CategoryKind.investment => 'INVESTED',
    CategoryKind.transfer => 'TRANSFER',
    CategoryKind.income => 'INCOME',
  };
}

/// What the seeded categories mean, and the fallback for a stored category
/// saved before kinds existed — or round-tripped through a build that predates
/// them, which drops the field.
///
/// A [ExpenseCategory.fromJson] default only, never a live lookup: renaming
/// "Rent" to "House rent" must not change what it means, and a kind the user
/// actually chose must always win.
const defaultCategoryKinds = <String, CategoryKind>{
  'rent': CategoryKind.committed,
  'bills': CategoryKind.committed,
  'subscriptions': CategoryKind.committed,
  'investment': CategoryKind.investment,
  'card bill': CategoryKind.transfer,
  'salary': CategoryKind.income,
};

/// A user-customizable expense category: a name plus its visual style
/// (an icon key from [CategoryStyles.iconOptions] and a hex color), and what
/// its spending means.
class ExpenseCategory {
  final String name;
  final String iconKey;
  final String colorHex; // #RRGGBB
  final CategoryKind kind;

  const ExpenseCategory({
    required this.name,
    required this.iconKey,
    required this.colorHex,
    this.kind = CategoryKind.everyday,
  });

  ExpenseCategory copyWith({
    String? name,
    String? iconKey,
    String? colorHex,
    CategoryKind? kind,
  }) {
    return ExpenseCategory(
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      colorHex: colorHex ?? this.colorHex,
      kind: kind ?? this.kind,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'iconKey': iconKey,
      'colorHex': colorHex,
      'kind': kind.name,
    };
  }

  factory ExpenseCategory.fromJson(Map<dynamic, dynamic> json) {
    final name = json['name'] as String;
    return ExpenseCategory(
      name: name,
      iconKey: json['iconKey'] as String? ?? 'category',
      colorHex: json['colorHex'] as String? ?? '#9AA1AD',
      // Absent: a pre-kinds list, or one saved by an older build. The name
      // table puts the seeded ones back. Unknown (a kind from a newer build)
      // reads as everyday rather than throwing — money must not vanish.
      kind:
          CategoryKind.values.asNameMap()[json['kind'] as String? ?? ''] ??
          defaultCategoryKinds[name.trim().toLowerCase()] ??
          CategoryKind.everyday,
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
  ExpenseCategory(
    name: 'Rent',
    iconKey: 'home',
    colorHex: '#D8A878',
    kind: CategoryKind.committed,
  ),
  ExpenseCategory(
    name: 'Bills',
    iconKey: 'receipt_long',
    colorHex: '#8FA3BF',
    kind: CategoryKind.committed,
  ),
  ExpenseCategory(
    name: 'Subscriptions',
    iconKey: 'subscriptions',
    colorHex: '#8F9FE0',
    kind: CategoryKind.committed,
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
    kind: CategoryKind.investment,
  ),
  ExpenseCategory(
    name: kProtectedCategoryName,
    iconKey: 'category',
    colorHex: '#9AA1AD',
  ),
];
