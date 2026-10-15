/// Riverpod state for the export flow (Agent E).
///
/// * [exportConfigProvider] — the UI-level preset/custom configuration.
/// * [exportControllerProvider] — runs/cancels the render and exposes
///   [ExportState] (idle / running + progress / done + path / error).
library;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whipcut/models/project.dart';

import 'export_engine.dart';

/// Lifecycle of one export run.
enum ExportStatus { idle, running, done, error }

/// Immutable snapshot of the export UI state.
class ExportState {
  final ExportStatus status;
  final double progress;
  final String? outputPath;
  final String? errorMessage;

  const ExportState._({
    required this.status,
    this.progress = 0.0,
    this.outputPath,
    this.errorMessage,
  });

  factory ExportState.idle() =>
      const ExportState._(status: ExportStatus.idle);

  factory ExportState.running(double progress) => ExportState._(
        status: ExportStatus.running,
        progress: progress.clamp(0.0, 1.0),
      );

  factory ExportState.done(String outputPath) => ExportState._(
        status: ExportStatus.done,
        progress: 1.0,
        outputPath: outputPath,
      );

  factory ExportState.error(String message) => ExportState._(
        status: ExportStatus.error,
        errorMessage: message,
      );
}

/// Runs the ffmpeg render and publishes progress.
class ExportController extends StateNotifier<ExportState> {
  ExportController(this._ref) : super(ExportState.idle());

  final Ref _ref;

  /// Starts rendering [project] with the current [ExportConfig].
  /// No-op while a render is already running.
  Future<void> startExport(WhipcutProject project) async {
    if (state.status == ExportStatus.running) return;
    final config = _ref.read(exportConfigProvider);
    state = ExportState.running(0);
    try {
      final settings = await config.resolve(project);
      final result = await renderProject(project, settings, (p) {
        if (mounted) state = ExportState.running(p);
      });
      if (!mounted) return;
      state = result.success && result.outputPath != null
          ? ExportState.done(result.outputPath!)
          : ExportState.error(result.errorMessage ?? 'Export failed.');
    } catch (e) {
      if (mounted) state = ExportState.error(e.toString());
    }
  }

  /// Cancels the in-flight ffmpeg session, if any.
  Future<void> cancelExport() => FFmpegKit.cancel();

  /// Back to idle (e.g. after showing the done/error card).
  void reset() {
    if (state.status != ExportStatus.running) {
      state = ExportState.idle();
    }
  }
}

/// UI-level export configuration (preset + custom controls).
final exportConfigProvider =
    StateProvider<ExportConfig>((ref) => const ExportConfig());

/// The export run controller.
final exportControllerProvider =
    StateNotifierProvider<ExportController, ExportState>(
  (ref) => ExportController(ref),
);
