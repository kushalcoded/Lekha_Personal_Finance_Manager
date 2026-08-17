import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The wall clock, as a provider.
///
/// Screens that print today's date render a different picture every day, which
/// made the golden harness fail on every screen for reasons that had nothing to
/// do with the code. Overriding this pins the clock so a re-shot golden stays
/// valid. Production reads the real clock.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);
