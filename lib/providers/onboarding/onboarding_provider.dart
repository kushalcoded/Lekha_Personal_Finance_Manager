import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage_providers.dart';

class OnboardingState {
  final bool isLoading;
  final bool isCompleted;
  final String? error;

  const OnboardingState({
    this.isLoading = true,
    this.isCompleted = false,
    this.error,
  });

  OnboardingState copyWith({
    bool? isLoading,
    bool? isCompleted,
    String? error,
  }) {
    return OnboardingState(
      isLoading: isLoading ?? this.isLoading,
      isCompleted: isCompleted ?? this.isCompleted,
      error: error,
    );
  }
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  final Ref _ref;

  OnboardingNotifier(this._ref) : super(const OnboardingState()) {
    load();
  }

  Future<void> load() async {
    try {
      final completed = _ref.read(hiveServiceProvider).isOnboardingCompleted();
      state = OnboardingState(isLoading: false, isCompleted: completed);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> complete() async {
    await _ref.read(hiveServiceProvider).setOnboardingCompleted(true);
    state = state.copyWith(isCompleted: true, isLoading: false, error: null);
  }

  Future<void> reset() async {
    await _ref.read(hiveServiceProvider).setOnboardingCompleted(false);
    state = state.copyWith(isCompleted: false, isLoading: false, error: null);
  }
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>(
      (ref) => OnboardingNotifier(ref),
    );
