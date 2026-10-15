import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences flag: true once the user finished or skipped the
/// first-run onboarding. Until then the onboarding shows on every launch.
@visibleForTesting
const onboardingDoneKey = 'whipcut_onboarding_done';

/// Whether the first-run onboarding has been completed.
final onboardingDoneProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(onboardingDoneKey) ?? false;
});

/// Marks onboarding complete ("Get started" or "Skip").
///
/// The flag is written only here, so quitting mid-onboarding shows it
/// again on the next launch.
class OnboardingController extends StateNotifier<AsyncValue<void>> {
  OnboardingController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  Future<void> markDone() async {
    state = const AsyncValue.loading();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(onboardingDoneKey, true);
      _ref.invalidate(onboardingDoneProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, AsyncValue<void>>(
        (ref) => OnboardingController(ref));
