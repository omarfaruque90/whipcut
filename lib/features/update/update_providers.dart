import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_service.dart';

/// Service singleton (injectable in tests via overrides).
final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

/// Installed app version, for the Settings/About row.
final installedVersionProvider = FutureProvider<String>((ref) async {
  return ref.watch(updateServiceProvider).getInstalledVersion();
});

/// Immutable update-check UI state.
class UpdateState {
  const UpdateState({
    this.available,
    this.checking = false,
    this.error,
  });

  /// Non-null when a newer release was found and not yet dismissed.
  final ReleaseInfo? available;
  final bool checking;
  final String? error;

  UpdateState copyWith({
    ReleaseInfo? available,
    bool? checking,
    String? error,
  }) =>
      UpdateState(
        available: available ?? this.available,
        checking: checking ?? this.checking,
        error: error,
      );

  /// Clears the pending prompt (does not clear the "prompted today" stamp).
  UpdateState dismissed() =>
      const UpdateState(available: null, checking: false);
}

/// Coordinates the update flow: startup check, manual check, download.
class UpdateController extends StateNotifier<UpdateState> {
  UpdateController(this._ref) : super(const UpdateState());

  final Ref _ref;

  /// SharedPreferences key for the last day the update dialog was shown.
  @visibleForTesting
  static const promptDateKey = 'whipcut_update_last_prompt';

  bool _startupChecked = false;

  /// One-time check on app start. Shows nothing on failure/offline, and
  /// never prompts twice on the same day ("Later" = snooze for today).
  Future<void> checkOnStartup() async {
    if (_startupChecked) return;
    _startupChecked = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (prefs.getString(promptDateKey) == today) return;

      final result = await _ref.read(updateServiceProvider).checkNow();
      if (result.available && result.release != null) {
        await prefs.setString(promptDateKey, today);
        state = state.copyWith(available: result.release);
      }
    } catch (_) {
      // Never break app start because of the update check.
    }
  }

  /// Manual check from Settings. Returns the release when an update is
  /// available, null otherwise (caller shows the "up to date" toast).
  Future<ReleaseInfo?> checkManually() async {
    state = state.copyWith(checking: true, error: null);
    try {
      final result = await _ref.read(updateServiceProvider).checkNow();
      final info = result.available ? result.release : null;
      state = state.copyWith(checking: false, available: info);
      return info;
    } catch (e) {
      state = state.copyWith(checking: false, error: e.toString());
      return null;
    }
  }

  /// Downloads the APK; returns the file or null on failure.
  Future<File?> downloadUpdate(
    ReleaseInfo info, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    try {
      return await _ref
          .read(updateServiceProvider)
          .downloadApk(info.apkUrl, onProgress: onProgress);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Launches the Android installer for a downloaded APK.
  Future<void> installUpdate(File apkFile) =>
      _ref.read(updateServiceProvider).installApk(apkFile);

  /// Dismisses the pending update prompt.
  void dismiss() {
    state = state.dismissed();
  }
}

final updateControllerProvider =
    StateNotifierProvider<UpdateController, UpdateState>(
        (ref) => UpdateController(ref));
