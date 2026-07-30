/// Calculator-style amount entry: '450+89', '450 89' and '450, 89' all mean
/// a sum; '500-60' subtracts. Used everywhere an amount is typed.
library;

final _separators = RegExp(r'[,\s]+');
final _numberToken = RegExp(r'[+-]?\d*\.?\d+');
final _validExpression = RegExp(r'^[+-]?\d*\.?\d+([+-]\d*\.?\d+)*$');

String _normalize(String raw) {
  var s = raw.trim().replaceAll('₹', '');
  s = s.replaceAll(_separators, '+');
  s = s.replaceAll(RegExp(r'\+{2,}'), '+');
  // Trailing/leading separator while mid-typing shouldn't kill the parse.
  s = s.replaceAll(RegExp(r'^\+|[+-]$'), '');
  return s;
}

/// The evaluated amount, or null when [raw] isn't a valid expression.
/// ponytail: comma is a separator, so a thousands-style "1,200" reads as
/// 1+200 — the live "= total" hint makes that visible before saving.
double? parseAmountExpression(String raw) {
  final s = _normalize(raw);
  if (s.isEmpty || !_validExpression.hasMatch(s)) return null;
  var total = 0.0;
  for (final m in _numberToken.allMatches(s)) {
    total += double.parse(m.group(0)!);
  }
  return total;
}

/// True when [raw] is a valid expression with more than one term — i.e. a
/// computed-total hint is worth showing.
bool isMultiTermAmount(String raw) {
  final s = _normalize(raw);
  if (!_validExpression.hasMatch(s)) return false;
  return _numberToken.allMatches(s).length > 1;
}
