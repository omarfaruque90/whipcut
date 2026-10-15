import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:whipcut/models/color_adjust.dart';
import 'package:whipcut/models/project.dart';
import 'package:whipcut/models/timeline.dart';

/// Editor agent (Agent C) providers.
///
/// [timelineEditorProvider] is a family keyed by the [WhipcutProject] being
/// edited. It holds the working [TimelineProject], the selection, playhead,
/// zoom and snap state, plus undo/redo snapshot stacks.

const _uuid = Uuid();

String newClipId() => _uuid.v4();
String newTrackId() => _uuid.v4();

/// Immutable editor state. The [project] is the undoable working copy.
class TimelineEditorState {
  final TimelineProject project;
  final String? selectedClipId;
  final double playhead;
  final double pxPerSecond;
  final bool snapEnabled;

  const TimelineEditorState({
    required this.project,
    this.selectedClipId,
    this.playhead = 0,
    this.pxPerSecond = 60,
    this.snapEnabled = true,
  });

  TimelineEditorState copyWith({
    TimelineProject? project,
    String? selectedClipId,
    bool clearSelection = false,
    double? playhead,
    double? pxPerSecond,
    bool? snapEnabled,
  }) {
    return TimelineEditorState(
      project: project ?? this.project,
      selectedClipId:
          clearSelection ? null : (selectedClipId ?? this.selectedClipId),
      playhead: playhead ?? this.playhead,
      pxPerSecond: pxPerSecond ?? this.pxPerSecond,
      snapEnabled: snapEnabled ?? this.snapEnabled,
    );
  }
}

/// Undoable timeline operations. Every mutation goes through [_commit],
/// which pushes the previous snapshot onto the undo stack.
class TimelineEditorNotifier extends StateNotifier<TimelineEditorState> {
  TimelineEditorNotifier(TimelineProject initial)
      : super(TimelineEditorState(project: initial));

  final List<TimelineProject> _undoStack = [];
  final List<TimelineProject> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Current playhead position in seconds (public read of state).
  double get playhead => state.playhead;

  /// Current timeline zoom in px per second (public read of state).
  double get pxPerSecond => state.pxPerSecond;

  /// Working timeline duration in seconds (public read of state).
  double get projectDuration => state.project.duration;

  void _commit(TimelineProject next) {
    _undoStack.add(state.project);
    _redoStack.clear();
    state = state.copyWith(project: next);
  }

  // Selection / transport -------------------------------------------------

  void selectClip(String? clipId) {
    state = state.copyWith(
      selectedClipId: clipId,
      clearSelection: clipId == null,
    );
  }

  void setPlayhead(double seconds) {
    final clamped = seconds.clamp(0.0, state.project.duration).toDouble();
    state = state.copyWith(playhead: clamped);
  }

  void setZoom(double pxPerSecond) {
    state = state.copyWith(
      pxPerSecond: pxPerSecond.clamp(16.0, 240.0).toDouble(),
    );
  }

  void toggleSnap() {
    state = state.copyWith(snapEnabled: !state.snapEnabled);
  }

  // Undo / redo -----------------------------------------------------------

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(state.project);
    state = state.copyWith(
      project: _undoStack.removeLast(),
      clearSelection: true,
    );
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(state.project);
    state = state.copyWith(
      project: _redoStack.removeLast(),
      clearSelection: true,
    );
  }

  // Clip lookup helpers ---------------------------------------------------

  ({TimelineTrack track, TimelineClip clip, int trackIndex, int clipIndex})?
      findClip(String clipId) {
    for (var ti = 0; ti < state.project.tracks.length; ti++) {
      final track = state.project.tracks[ti];
      for (var ci = 0; ci < track.clips.length; ci++) {
        if (track.clips[ci].id == clipId) {
          return (track: track, clip: track.clips[ci], trackIndex: ti, clipIndex: ci);
        }
      }
    }
    return null;
  }

  TimelineProject _replaceClip(
      int trackIndex, int clipIndex, TimelineClip replacement) {
    final tracks = List<TimelineTrack>.of(state.project.tracks);
    final track = tracks[trackIndex];
    final clips = List<TimelineClip>.of(track.clips);
    clips[clipIndex] = replacement;
    tracks[trackIndex] = track.copyWith(clips: clips);
    return state.project.copyWith(tracks: tracks);
  }

  TimelineProject _replaceTrackClips(int trackIndex, List<TimelineClip> clips) {
    final tracks = List<TimelineTrack>.of(state.project.tracks);
    tracks[trackIndex] =
        tracks[trackIndex].copyWith(clips: clips);
    return state.project.copyWith(tracks: tracks);
  }

  // Import ----------------------------------------------------------------

  /// Adds a clip to the first track of [type], creating the track if needed.
  /// The clip is appended at the end of the track.
  void addClip(TrackType type, TimelineClip clip) {
    var tracks = List<TimelineTrack>.of(state.project.tracks);
    var trackIndex = tracks.indexWhere((t) => t.type == type);
    if (trackIndex < 0) {
      tracks.add(TimelineTrack(id: newTrackId(), type: type));
      trackIndex = tracks.length - 1;
    }
    final track = tracks[trackIndex];
    final appended = clip.copyWith(start: track.end);
    final clips = List<TimelineClip>.of(track.clips)..add(appended);
    tracks[trackIndex] = track.copyWith(clips: clips);
    _commit(state.project.copyWith(tracks: tracks));
    selectClip(appended.id);
  }

  // Trim ------------------------------------------------------------------

  /// Trims [clipId] to the source range [newSourceStart]..[newSourceEnd]
  /// (seconds into the source media). The timeline position stays fixed.
  void trimClip(String clipId, double newSourceStart, double newSourceEnd) {
    final found = findClip(clipId);
    if (found == null) return;
    var s = newSourceStart.clamp(0.0, double.infinity);
    var e = newSourceEnd;
    if (e <= s) return;
    final duration = e - s;
    final trimmed = found.clip.copyWith(sourceStart: s, duration: duration);
    _commit(_replaceClip(found.trackIndex, found.clipIndex, trimmed));
  }

  // Split -----------------------------------------------------------------

  /// Splits the clip at [atSeconds] (timeline time) into two clips.
  /// Returns false when the playhead is not strictly inside a clip.
  bool splitClipAt(String clipId, double atSeconds) {
    final found = findClip(clipId);
    if (found == null) return false;
    final clip = found.clip;
    if (atSeconds <= clip.start || atSeconds >= clip.end) return false;

    final firstDuration = atSeconds - clip.start;
    final secondDuration = clip.end - atSeconds;
    // Source mapping under the fixed-duration speed model:
    // timeline span T consumes T * speed seconds of source.
    final secondSourceStart =
        clip.sourceStart + firstDuration * clip.speed;

    final first = clip.copyWith(duration: firstDuration);
    final second = TimelineClip(
      id: newClipId(),
      mediaPath: clip.mediaPath,
      start: atSeconds,
      duration: secondDuration,
      sourceStart: secondSourceStart,
      speed: clip.speed,
      reversed: clip.reversed,
      volume: clip.volume,
      fadeIn: 0,
      fadeOut: clip.fadeOut,
      colorAdjust: clip.colorAdjust,
    );

    final clips = List<TimelineClip>.of(found.track.clips);
    clips[found.clipIndex] = first;
    clips.insert(found.clipIndex + 1, second);
    _commit(_replaceTrackClips(found.trackIndex, clips));
    selectClip(second.id);
    return true;
  }

  // Ripple delete ----------------------------------------------------------

  /// Removes the clip and shifts later clips on the same track left.
  void rippleDelete(String clipId) {
    final found = findClip(clipId);
    if (found == null) return;
    final removed = found.clip;
    final clips = <TimelineClip>[];
    for (final c in found.track.clips) {
      if (c.id == clipId) continue;
      if (c.start > removed.start) {
        clips.add(c.copyWith(start: c.start - removed.duration));
      } else {
        clips.add(c);
      }
    }
    _commit(_replaceTrackClips(found.trackIndex, clips));
    selectClip(null);
  }

  // Speed / reverse ---------------------------------------------------------

  void setSpeed(String clipId, double speed) {
    final found = findClip(clipId);
    if (found == null) return;
    final clamped = speed.clamp(0.25, 4.0).toDouble();
    _commit(_replaceClip(
      found.trackIndex,
      found.clipIndex,
      found.clip.copyWith(speed: clamped),
    ));
  }

  void toggleReverse(String clipId) {
    final found = findClip(clipId);
    if (found == null) return;
    _commit(_replaceClip(
      found.trackIndex,
      found.clipIndex,
      found.clip.copyWith(reversed: !found.clip.reversed),
    ));
  }

  // Snapping ----------------------------------------------------------------

  /// Replaces the working timeline with [timeline] coming from outside the
  /// editor (e.g. a panel screen that edited `currentProjectProvider`).
  /// Keeps the undo/redo history; clears the selection.
  /// (Integration, 2026-10-15.)
  void adoptExternalTimeline(TimelineProject timeline) {
    if (timeline == state.project) return;
    state = state.copyWith(project: timeline, clearSelection: true);
  }

  /// Snaps [time] to the nearest clip edge (all tracks) within [thresholdPx].
  double snapTime(double time, double thresholdPx) {
    if (!state.snapEnabled) return time;
    final threshold = thresholdPx / state.pxPerSecond;
    double best = time;
    var bestDist = threshold;
    for (final track in state.project.tracks) {
      for (final clip in track.clips) {
        for (final edge in [clip.start, clip.end]) {
          final dist = (edge - time).abs();
          if (dist < bestDist) {
            bestDist = dist;
            best = edge;
          }
        }
      }
    }
    return best;
  }

  // Preview helper ------------------------------------------------------------

  /// The first video clip whose file exists — used for the preview player.
  TimelineClip? get firstPlayableVideoClip {
    for (final track in state.project.tracks) {
      if (track.type != TrackType.video) continue;
      for (final clip in track.clips) {
        if (File(clip.mediaPath).existsSync()) return clip;
      }
    }
    return null;
  }
}

/// Working timeline editor state, keyed by the project being edited.
final timelineEditorProvider = StateNotifierProvider.family<
    TimelineEditorNotifier, TimelineEditorState, WhipcutProject>(
  (ref, project) => TimelineEditorNotifier(project.timeline),
);

/// Probes a local video file for its duration in seconds.
Future<double> probeVideoDuration(String path) async {
  final controller = VideoPlayerController.file(File(path));
  try {
    await controller.initialize();
    return controller.value.duration.inMilliseconds / 1000.0;
  } finally {
    await controller.dispose();
  }
}

/// Copies a picked video into Whipcut's private media store and returns the
/// new path.
///
/// The system picker may hand back cache or content-provider paths that can
/// vanish or become unreadable later (which left the editor preview black
/// with a dead play button). Clips always reference our own copy, so the
/// file is guaranteed to exist for preview, export and reopened projects.
Future<String> copyPickedVideoToAppStorage(String pickedPath) async {
  final source = File(pickedPath);
  if (!await source.exists()) {
    throw FileSystemException('Picked video not found', pickedPath);
  }
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/whipcut_media');
  if (!await dir.exists()) await dir.create(recursive: true);
  var ext = '';
  final dot = pickedPath.lastIndexOf('.');
  final sep = pickedPath.lastIndexOf('/');
  if (dot > sep) ext = pickedPath.substring(dot);
  final target = File('${dir.path}/${newClipId()}$ext');
  await source.copy(target.path);
  return target.path;
}

/// Builds a fresh video clip from an imported file.
TimelineClip buildImportedVideoClip({
  required String mediaPath,
  required double sourceDuration,
}) {
  return TimelineClip(
    id: newClipId(),
    mediaPath: mediaPath,
    start: 0,
    duration: sourceDuration > 0 ? sourceDuration : 1.0,
    sourceStart: 0,
    speed: 1.0,
    reversed: false,
    volume: 1.0,
    fadeIn: 0,
    fadeOut: 0,
    colorAdjust: ColorAdjust.identity,
  );
}
