import 'package:flutter/foundation.dart';

@immutable
class PersonBalance {
  final String person;
  final double receivableTotal;
  final double payableTotal;

  const PersonBalance({
    required this.person,
    required this.receivableTotal,
    required this.payableTotal,
  });

  double get netBalance => receivableTotal - payableTotal;
}
