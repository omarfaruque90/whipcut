/// Whipcut export engine — pure-Dart ffmpeg command builder + FFmpegKit runner.
///
/// Owned by Agent E. Only files under `lib/features/export/` may be edited.
///
/// Design:
/// * `preparePlan()` gathers everything the render needs (clip order, audio
///   presence via ffprobe, runtime font resolution) into an [ExportPlan].
/// * `buildArguments()` / `buildCommand()` are PURE functions of
///   `(ExportPlan, ExportSettings, outputPath)` — unit-testable, no I/O.
/// * `renderProject()` wires plan -> command -> FFmpegKit execution with a
///   [Statistics] progress callback and [ReturnCode] handling.
///
/// Model contracts (provided by sibling agents, not yet landed):
/// * `package:whipcut/models/project.dart` — WhipcutProject(id, name,
///   aspectRatio, timeline); AspectRatioPreset(r16x9/r9x16/r1x1/r4x5)
///   with `.ratio` and `.label`.
/// * `package:whipcut/models/timeline.dart` — TimelineProject(tracks,
///   textOverlays, duration); TimelineTrack(id, type, clips);
///   TrackType(video/audio/text); TimelineClip(id, mediaPath, start,
///   duration, sourceStart, speed, reversed, volume, fadeIn, fadeOut,
///   colorAdjust).
/// * `package:whipcut/models/color_adjust.dart` — ColorAdjust(exposure,
///   contrast, saturation, temperature, lutPath).
/// * `package:whipcut/models/text_overlay.dart` — TextOverlay(text, fontSize,
///   color [ARGB int], x, y [0..1], start, duration, bold).
///
/// Assumptions (see REPORT for integration notes):
/// * ColorAdjust ranges (landed 2026-10-15): exposure -2..2 EV (mapped to
///   eq brightness via exposure*0.15), contrast/saturation multipliers
///   0..2 (1 = neutral), temperature -1..1 (cool..warm) mapped to
///   3000..9000K for colortemperature.
/// * Video clips are concatenated in timeline `start` order. Overlapping
///   video clips on multiple tracks are NOT composited in Phase 1 — they
///   play back-to-back in start order.
/// * Input trimming uses fast input seeking (`-ss`/`-t` before `-i`).
/// * Audio clips carry placeholder durations (the timeline length at the
///   moment the user added them — see the audio screen). `preparePlan`
///   re-probes each audio source with ffprobe and renders the real duration
///   (extend/truncate); if probing fails it falls back to the stored value.
///   Audio shorter than the timeline is padded with silence (`apad`) — this
///   path never crashes.
/// * drawtext requires the ffmpeg build to include libfreetype
///   (ffmpeg_kit_flutter_new full package). If no system font is found,
///   text overlays are skipped gracefully with a warning.
/// * NO WATERMARK is ever added — only user text overlays.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:path_provider/path_provider.dart';

import 'package:whipcut/models/project.dart';
import 'package:whipcut/models/text_overlay.dart';
import 'package:whipcut/models/timeline.dart';

// ---------------------------------------------------------------------------
// Public settings / config models
// ---------------------------------------------------------------------------

/// Output video codec.
enum ExportCodec { h264, h265 }

/// Preset selector shown on the export screen.
enum ExportPreset { youtube4k, reels, custom }

/// Resolution choices for the custom preset.
enum ExportResolution { p720, p1080, p2160, original }

/// Fully-resolved render settings — everything the command builder needs.
class ExportSettings {
  final int width;
  final int height;
  final int fps;
  final double bitrateMbps;
  final ExportCodec codec;

  const ExportSettings({
    required this.width,
    required this.height,
    required this.fps,
    required this.bitrateMbps,
    required this.codec,
  });

  /// "YouTube 4K" preset: 3840x2160, 30fps, 20Mbps, H.264.
  factory ExportSettings.youtube4k() => const ExportSettings(
        width: 3840,
        height: 2160,
        fps: 30,
        bitrateMbps: 20,
        codec: ExportCodec.h264,
      );

  /// "Reels / TikTok" preset: 1080x1920, 30fps, 12Mbps, H.264.
  factory ExportSettings.reels() => const ExportSettings(
        width: 1080,
        height: 1920,
        fps: 30,
        bitrateMbps: 12,
        codec: ExportCodec.h264,
      );

  String get videoCodecName =>
      codec == ExportCodec.h264 ? 'libx264' : 'libx265';
}

/// UI-level export configuration. `resolve()` turns it into [ExportSettings],
/// probing the source when "original" resolution is selected.
class ExportConfig {
  final ExportPreset preset;
  final ExportResolution resolution;
  final int fps;
  final double bitrateMbps;
  final ExportCodec codec;

  const ExportConfig({
    this.preset = ExportPreset.youtube4k,
    this.resolution = ExportResolution.p1080,
    this.fps = 30,
    this.bitrateMbps = 12,
    this.codec = ExportCodec.h264,
  });

  ExportConfig copyWith({
    ExportPreset? preset,
    ExportResolution? resolution,
    int? fps,
    double? bitrateMbps,
    ExportCodec? codec,
  }) =>
      ExportConfig(
        preset: preset ?? this.preset,
        resolution: resolution ?? this.resolution,
        fps: fps ?? this.fps,
        bitrateMbps: bitrateMbps ?? this.bitrateMbps,
        codec: codec ?? this.codec,
      );

  Future<ExportSettings> resolve(WhipcutProject project) async {
    switch (preset) {
      case ExportPreset.youtube4k:
        return ExportSettings.youtube4k();
      case ExportPreset.reels:
        return ExportSettings.reels();
      case ExportPreset.custom:
        final dims = await _resolveCustomDims(project);
        return ExportSettings(
          width: dims.$1,
          height: dims.$2,
          fps: fps,
          bitrateMbps: bitrateMbps,
          codec: codec,
        );
    }
  }

  Future<(int, int)> _resolveCustomDims(WhipcutProject project) async {
    final ratio = project.aspectRatio.ratio;
    switch (resolution) {
      case ExportResolution.p720:
        return (_even((720 * ratio).round()), 720);
      case ExportResolution.p1080:
        return (_even((1080 * ratio).round()), 1080);
      case ExportResolution.p2160:
        return (_even((2160 * ratio).round()), 2160);
      case ExportResolution.original:
        final first = _videoClips(project).firstOrNull;
        if (first != null) {
          final probed = await _probeVideoDims(first.mediaPath);
          if (probed != null) return probed;
        }
        return (_even((1080 * ratio).round()), 1080);
    }
  }
}

/// Result of a render.
class ExportResult {
  final bool success;
  final String? outputPath;
  final String? errorMessage;
  final List<String> warnings;

  const ExportResult({
    required this.success,
    this.outputPath,
    this.errorMessage,
    this.warnings = const [],
  });
}

// ---------------------------------------------------------------------------
// Render plan (prepared once, then fed to the pure builders)
// ---------------------------------------------------------------------------

/// A video-track clip plus whether its source file carries an audio stream.
class PlannedVideoClip {
  final TimelineClip clip;
  final bool hasAudio;

  const PlannedVideoClip({required this.clip, required this.hasAudio});
}

/// Everything [buildArguments]/[buildCommand] need. Constructible in tests
/// without touching ffprobe or the filesystem.
class ExportPlan {
  final List<PlannedVideoClip> videoClips;
  final List<TimelineClip> audioClips;
  final List<TextOverlay> textOverlays;
  final double totalDuration;
  final String? fontPath;
  final String? fontBoldPath;
  final List<String> warnings;

  const ExportPlan({
    required this.videoClips,
    required this.audioClips,
    required this.textOverlays,
    required this.totalDuration,
    this.fontPath,
    this.fontBoldPath,
    this.warnings = const [],
  });
}

/// Builds an [ExportPlan] from the project: orders clips, probes each unique
/// source for an audio stream, re-probes audio-clip durations (imported and
/// recorded clips carry placeholder durations), and resolves a runtime font
/// for drawtext.
Future<ExportPlan> preparePlan(WhipcutProject project) async {
  final warnings = <String>[];
  final videoClips = _videoClips(project)
      .where((c) => c.duration > 0)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  // Audio durations are placeholders until re-probed here: one ffprobe per
  // unique path (cached), fallback to the stored duration on failure.
  final probedDurations = <String, double?>{};
  final audioClips = <TimelineClip>[];
  for (final c in _audioClips(project)) {
    if (!probedDurations.containsKey(c.mediaPath)) {
      probedDurations[c.mediaPath] = await _probeAudioDuration(c.mediaPath);
    }
    final probed = probedDurations[c.mediaPath];
    final effective = c.copyWith(
      duration: (probed != null && probed > 0) ? probed : c.duration,
    );
    if (effective.duration > 0) audioClips.add(effective);
  }
  audioClips.sort((a, b) => a.start.compareTo(b.start));

  final hasAudio = <String, bool>{};
  for (final path in videoClips.map((c) => c.mediaPath).toSet()) {
    hasAudio[path] = await _probeHasAudio(path);
  }

  final font = await _resolveFont();
  if (font.regular == null &&
      project.timeline.textOverlays.any((t) => t.text.trim().isNotEmpty)) {
    warnings.add('No system font found — text overlays were skipped.');
  }

  // Extend the render to cover audio that runs past the video timeline.
  var totalDuration = project.timeline.duration;
  for (final c in audioClips) {
    if (c.end > totalDuration) totalDuration = c.end;
  }

  return ExportPlan(
    videoClips: [
      for (final c in videoClips)
        PlannedVideoClip(clip: c, hasAudio: hasAudio[c.mediaPath] ?? false),
    ],
    audioClips: audioClips,
    textOverlays: project.timeline.textOverlays
        .where((t) => t.text.trim().isNotEmpty && t.duration > 0)
        .toList(),
    totalDuration: totalDuration,
    fontPath: font.regular,
    fontBoldPath: font.bold,
    warnings: warnings,
  );
}

List<TimelineClip> _videoClips(WhipcutProject project) => project
    .timeline.tracks
    .where((t) => t.type == TrackType.video)
    .expand((t) => t.clips)
    .toList();

List<TimelineClip> _audioClips(WhipcutProject project) => project
    .timeline.tracks
    .where((t) => t.type == TrackType.audio)
    .expand((t) => t.clips)
    .toList();

Future<bool> _probeHasAudio(String path) async {
  try {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    if (info == null) return true;
    return info.getStreams().any((s) => s.getType() == 'audio');
  } catch (_) {
    // If probing fails the render would fail at the input anyway; assume
    // audio exists so a transient probe error doesn't mute camera audio.
    return true;
  }
}

/// Re-probes an audio file's real duration in seconds.
///
/// Imported/recorded clips carry placeholder durations (the timeline length
/// when they were added). Returns null when probing fails so the caller can
/// fall back to the stored value — never throws, never fatal.
Future<double?> _probeAudioDuration(String path) async {
  try {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    if (info == null) return null;
    final fromInfo = double.tryParse(info.getDuration() ?? '');
    if (fromInfo != null && fromInfo > 0) return fromInfo;
    for (final s in info.getStreams()) {
      if (s.getType() == 'audio') {
        final d =
            double.tryParse(s.getProperty('duration')?.toString() ?? '');
        if (d != null && d > 0) return d;
      }
    }
  } catch (_) {}
  return null;
}

Future<(int, int)?> _probeVideoDims(String path) async {
  try {
    final session = await FFprobeKit.getMediaInformation(path);
    final streams = session.getMediaInformation()?.getStreams() ?? [];
    for (final s in streams) {
      if (s.getType() == 'video') {
        final w = (s.getProperty('width') as num?)?.toInt();
        final h = (s.getProperty('height') as num?)?.toInt();
        if (w != null && h != null && w > 0 && h > 0) {
          return (_even(w), _even(h));
        }
      }
    }
  } catch (_) {}
  return null;
}

const _regularFontCandidates = [
  '/system/fonts/Roboto-Regular.ttf',
  '/system/fonts/NotoSans-Regular.ttf',
  '/system/fonts/DroidSans.ttf',
];

const _boldFontCandidates = [
  '/system/fonts/Roboto-Bold.ttf',
  '/system/fonts/NotoSans-Bold.ttf',
  '/system/fonts/DroidSans-Bold.ttf',
];

Future<({String? regular, String? bold})> _resolveFont() async {
  String? pick(List<String> candidates) {
    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  return (
    regular: pick(_regularFontCandidates),
    bold: pick(_boldFontCandidates),
  );
}

// ---------------------------------------------------------------------------
// Pure command builders (no I/O — safe to unit test)
// ---------------------------------------------------------------------------

/// Builds the ffmpeg argument list. Pure function of its inputs.
List<String> buildArguments(
  ExportPlan plan,
  ExportSettings settings,
  String outputPath,
) {
  final args = <String>[];

  // Inputs: fast input seeking trims each clip to its used source range.
  // sourceDuration = timeline duration * speed (setpts/atempo restore timing).
  for (final vc in plan.videoClips) {
    final c = vc.clip;
    args.addAll([
      '-ss',
      _f(c.sourceStart),
      '-t',
      _f(c.duration * c.speed),
      '-i',
      c.mediaPath,
    ]);
  }
  for (final c in plan.audioClips) {
    args.addAll([
      '-ss',
      _f(c.sourceStart),
      '-t',
      _f(c.duration * c.speed),
      '-i',
      c.mediaPath,
    ]);
  }

  final graph = _buildFilterGraph(plan, settings);
  args.addAll(['-filter_complex', graph.filter]);

  args.addAll([
    '-map',
    graph.videoOut,
    '-c:v',
    settings.videoCodecName,
    '-preset',
    'veryfast',
    '-b:v',
    '${_f(settings.bitrateMbps)}M',
    '-maxrate',
    '${_f(settings.bitrateMbps)}M',
    '-bufsize',
    '${_f(settings.bitrateMbps * 2)}M',
    '-r',
    '${settings.fps}',
    '-pix_fmt',
    'yuv420p',
  ]);

  if (graph.hasAudio) {
    args.addAll(['-map', '[aout]', '-c:a', 'aac', '-b:a', '128k']);
  }

  args.addAll(['-movflags', '+faststart', '-y', outputPath]);
  return args;
}

/// Builds the full command as a single shell-quoted string.
/// Pure function — for logging, tests, and display.
String buildCommand(
  ExportPlan plan,
  ExportSettings settings,
  String outputPath,
) =>
    buildArguments(plan, settings, outputPath).map(_shellQuote).join(' ');

({String filter, String videoOut, bool hasAudio}) _buildFilterGraph(
  ExportPlan plan,
  ExportSettings settings,
) {
  final sb = StringBuffer();

  // Per-clip video chains -> [vN]
  final videoLabels = <String>[];
  for (var i = 0; i < plan.videoClips.length; i++) {
    final label = '[v$i]';
    videoLabels.add(label);
    sb.write('[$i:v]${_videoChain(plan.videoClips[i].clip, settings)}$label;');
  }

  // Concat all video segments back-to-back.
  sb.write('${videoLabels.join()}'
      'concat=n=${videoLabels.length}:v=1:a=0[vcat];');
  var videoOut = '[vcat]';

  // User text overlays via drawtext (skipped gracefully when no font).
  if (plan.fontPath != null) {
    for (var i = 0; i < plan.textOverlays.length; i++) {
      final next = '[vt$i]';
      sb.write('$videoOut'
          '${_drawtextFilter(plan.textOverlays[i], plan, settings)}'
          '$next;');
      videoOut = next;
    }
  }

  // Per-clip audio chains -> [aN]. Video-clip audio keeps timeline position
  // (concat order); music/voiceover clips are delayed to their start offset.
  final audioLabels = <String>[];
  for (var i = 0; i < plan.videoClips.length; i++) {
    final planned = plan.videoClips[i];
    if (!planned.hasAudio || planned.clip.volume <= 0) continue;
    final label = '[a${audioLabels.length}]';
    audioLabels.add(label);
    sb.write('[$i:a]'
        '${_audioChain(planned.clip, plan.totalDuration, delaySeconds: 0)}'
        '$label;');
  }
  for (var j = 0; j < plan.audioClips.length; j++) {
    final clip = plan.audioClips[j];
    if (clip.volume <= 0) continue;
    final inputIndex = plan.videoClips.length + j;
    final label = '[a${audioLabels.length}]';
    audioLabels.add(label);
    sb.write('[$inputIndex:a]'
        '${_audioChain(clip, plan.totalDuration, delaySeconds: clip.start)}'
        '$label;');
  }

  var hasAudio = false;
  if (audioLabels.isNotEmpty) {
    hasAudio = true;
    sb.write('${audioLabels.join()}'
        'amix=inputs=${audioLabels.length}:duration=longest[aout]');
  }

  return (filter: sb.toString(), videoOut: videoOut, hasAudio: hasAudio);
}

/// Video filter chain for one clip: speed -> color -> scale/pad -> fps.
String _videoChain(TimelineClip clip, ExportSettings s) {
  final parts = <String>[];
  if (clip.reversed) parts.add('reverse');
  if ((clip.speed - 1.0).abs() > 1e-6) {
    parts.add('setpts=PTS/${_f(clip.speed)}');
  }

  // colorAdjust is non-nullable (ColorAdjust.identity = neutral).
  final adj = clip.colorAdjust;
  final needsEq =
      adj.exposure != 0 || adj.contrast != 1 || adj.saturation != 1;
  if (needsEq) {
    parts.add('eq=brightness=${_f(adj.exposure * 0.15)}'
        ':contrast=${_f(adj.contrast)}'
        ':saturation=${_f(adj.saturation)}');
  }
  if (adj.temperature.abs() > 1e-6) {
    final kelvin =
        (6000 + adj.temperature * 3000).round().clamp(3000, 9000);
    parts.add('colortemperature=temperature=$kelvin');
  }
  // One-tap filter presets (Agent F): lifted blacks and teal-orange grade.
  if (adj.lift > 1e-6) {
    parts.add("curves=all='0/${_f(adj.lift.clamp(0.0, 0.5))} 1/1'");
  }
  if (adj.tealOrange > 1e-6) {
    final t = adj.tealOrange.clamp(0.0, 1.0);
    parts.add('colorbalance='
        'gs=${_f(0.2 * t)}:bs=${_f(0.3 * t)}:'
        'rh=${_f(0.2 * t)}:gh=${_f(0.1 * t)}');
  }
  final lutPath = adj.lutPath;
  if (lutPath != null && lutPath.isNotEmpty) {
    parts.add("lut3d=file='${_escapeFilterArg(lutPath)}'");
  }

  // Fit into the target frame, letterbox/pillarbox with the Whipcut dark.
  parts.add('scale=${s.width}:${s.height}:force_original_aspect_ratio=decrease');
  parts.add('pad=${s.width}:${s.height}:(ow-iw)/2:(oh-ih)/2:color=0x101012');
  parts.add('setsar=1');
  parts.add('fps=${s.fps}');
  parts.add('format=yuv420p');
  return parts.join(',');
}

/// Audio filter chain for one clip: speed -> reverse -> volume -> fades ->
/// timeline placement -> pad/trim to full duration -> normalize format.
String _audioChain(
  TimelineClip clip,
  double totalDuration, {
  required double delaySeconds,
}) {
  final parts = <String>['aresample=48000'];
  final atempo = _atempoChain(clip.speed);
  if (atempo != null) parts.add(atempo);
  if (clip.reversed) parts.add('areverse');
  if ((clip.volume - 1.0).abs() > 1e-6) {
    parts.add('volume=${_f(clip.volume.clamp(0.0, 1.0))}');
  }
  if (clip.fadeIn > 0) {
    parts.add('afade=t=in:st=0:d=${_f(clip.fadeIn)}');
  }
  if (clip.fadeOut > 0) {
    final st = math.max(0.0, clip.duration - clip.fadeOut);
    parts.add('afade=t=out:st=${_f(st)}:d=${_f(clip.fadeOut)}');
  }
  if (delaySeconds > 0) {
    parts.add('adelay=delays=${(delaySeconds * 1000).round()}:all=1');
  }
  parts.add('apad=whole_dur=${_f(totalDuration)}');
  parts.add('atrim=duration=${_f(totalDuration)}');
  parts.add('aformat=sample_fmts=fltp:channel_layouts=stereo');
  return parts.join(',');
}

/// Chains atempo filters to cover 0.25x-4x (atempo itself supports 0.5-2.0).
String? _atempoChain(double speed) {
  if ((speed - 1.0).abs() < 1e-6) return null;
  final parts = <String>[];
  var s = speed;
  while (s > 2.0 + 1e-9) {
    parts.add('atempo=${_f(2.0)}');
    s /= 2.0;
  }
  while (s < 0.5 - 1e-9) {
    parts.add('atempo=${_f(0.5)}');
    s *= 2.0;
  }
  if ((s - 1.0).abs() > 1e-6) parts.add('atempo=${_f(s)}');
  return parts.isEmpty ? null : parts.join(',');
}

String _drawtextFilter(
  TextOverlay overlay,
  ExportPlan plan,
  ExportSettings s,
) {
  final font = (overlay.bold && plan.fontBoldPath != null)
      ? plan.fontBoldPath!
      : plan.fontPath!;
  // Scale authored font size (authored against 1080p) to output height.
  final px = (overlay.fontSize * s.height / 1080).round().clamp(8, 512);
  final argb = overlay.color.toRadixString(16).padLeft(8, '0').toUpperCase();
  final x = (s.width * overlay.x.clamp(0.0, 1.0)).round();
  final y = (s.height * overlay.y.clamp(0.0, 1.0)).round();
  final end = overlay.start + overlay.duration;
  return "drawtext=fontfile='${_escapeFilterArg(font)}'"
      ":text='${_escapeDrawText(overlay.text)}'"
      ':fontsize=$px'
      ':fontcolor=0x$argb'
      ':x=$x:y=$y'
      ":enable='between(t,${_f(overlay.start)},${_f(end)})'";
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

/// Renders [project] with [settings], reporting 0..1 progress via
/// [onProgress] (mapped from ffmpeg statistics time vs total duration).
///
/// Output: `<app documents>/WhipcutExports/whipcut_<timestamp>.mp4`.
Future<ExportResult> renderProject(
  WhipcutProject project,
  ExportSettings settings,
  void Function(double progress) onProgress,
) async {
  final plan = await preparePlan(project);
  if (plan.videoClips.isEmpty) {
    return const ExportResult(
      success: false,
      errorMessage: 'No video clips to export.',
    );
  }

  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/WhipcutExports');
  await dir.create(recursive: true);
  final stamp = _timestamp();
  final outputPath = '${dir.path}/whipcut_$stamp.mp4';

  final args = buildArguments(plan, settings, outputPath);
  final totalMs = (plan.totalDuration * 1000).round();

  try {
    final completer = Completer<FFmpegSession>();
    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) {
        if (!completer.isCompleted) completer.complete(session);
      },
      null,
      (Statistics stats) {
        if (totalMs > 0) {
          onProgress((stats.getTime() / totalMs).clamp(0.0, 1.0));
        }
      },
    );
    final session = await completer.future;
    final rc = await session.getReturnCode();

    if (ReturnCode.isSuccess(rc)) {
      onProgress(1.0);
      return ExportResult(
        success: true,
        outputPath: outputPath,
        warnings: plan.warnings,
      );
    }
    if (ReturnCode.isCancel(rc)) {
      return const ExportResult(
        success: false,
        errorMessage: 'Export cancelled.',
      );
    }
    final log = await session.getOutput() ?? '';
    return ExportResult(
      success: false,
      errorMessage:
          'ffmpeg failed (code ${rc?.getValue()}). ${_tail(log, 600)}',
      warnings: plan.warnings,
    );
  } catch (e) {
    return ExportResult(
      success: false,
      errorMessage: 'Export failed to start: $e',
      warnings: plan.warnings,
    );
  }
}

/// Cancels any in-flight ffmpeg session (wired to the UI cancel button).
Future<void> cancelExport() => FFmpegKit.cancel();

String _timestamp() {
  final n = DateTime.now();
  String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
  return '${n.year}${p(n.month)}${p(n.day)}_${p(n.hour)}${p(n.minute)}${p(n.second)}';
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

int _even(int v) => v.isEven ? v : v + 1;

/// Formats a double for ffmpeg args: "30" not "30.000", "1.5" not "1.500".
String _f(double v) =>
    v.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');

/// Escapes a path/value embedded in a single-quoted ffmpeg filter argument.
String _escapeFilterArg(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll("'", "\\'")
    .replaceAll(':', '\\:');

/// Escapes overlay text for drawtext's text='...' value.
String _escapeDrawText(String text) => _escapeFilterArg(text)
    .replaceAll('\n', ' ')
    .replaceAll('\r', ' ');

/// Shell-quotes one argument for the display/test command string.
String _shellQuote(String arg) {
  if (RegExp(r'''[\s'"\\]''').hasMatch(arg)) {
    return "'${arg.replaceAll("'", "'\\''")}'";
  }
  return arg;
}

String _tail(String s, int maxChars) =>
    s.length <= maxChars ? s : '…${s.substring(s.length - maxChars)}';
