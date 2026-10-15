import 'package:whipcut/models/color_adjust.dart';
import 'package:whipcut/models/text_overlay.dart';

/// Shared timeline model — owned by the editor agent (Agent C).
///
/// Every feature agent codes against these exact classes:
/// [TimelineClip], [TimelineTrack], [TimelineProject], [TrackType].

/// A timeline lane. `video` and `audio` hold [TimelineClip]s;
/// `text` lanes hold text clips (rendered from [TimelineProject.textOverlays]).
enum TrackType { video, audio, text }

/// A single media segment on a track.
///
/// - [start]: position on the timeline, in seconds.
/// - [duration]: trimmed length on the timeline, in seconds.
/// - [sourceStart]: offset into the source media, in seconds.
/// - [speed]: playback rate 0.25..4.0. The timeline [duration] stays fixed;
///   the export engine compensates with `setpts`.
class TimelineClip {
  final String id;
  final String mediaPath;
  final double start;
  final double duration;
  final double sourceStart;
  final double speed;
  final bool reversed;
  final double volume;
  final double fadeIn;
  final double fadeOut;
  final ColorAdjust colorAdjust;

  const TimelineClip({
    required this.id,
    required this.mediaPath,
    required this.start,
    required this.duration,
    this.sourceStart = 0,
    this.speed = 1.0,
    this.reversed = false,
    this.volume = 1.0,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.colorAdjust = ColorAdjust.identity,
  });

  double get end => start + duration;

  TimelineClip copyWith({
    String? id,
    String? mediaPath,
    double? start,
    double? duration,
    double? sourceStart,
    double? speed,
    bool? reversed,
    double? volume,
    double? fadeIn,
    double? fadeOut,
    ColorAdjust? colorAdjust,
  }) {
    return TimelineClip(
      id: id ?? this.id,
      mediaPath: mediaPath ?? this.mediaPath,
      start: start ?? this.start,
      duration: duration ?? this.duration,
      sourceStart: sourceStart ?? this.sourceStart,
      speed: speed ?? this.speed,
      reversed: reversed ?? this.reversed,
      volume: volume ?? this.volume,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      colorAdjust: colorAdjust ?? this.colorAdjust,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mediaPath': mediaPath,
        'start': start,
        'duration': duration,
        'sourceStart': sourceStart,
        'speed': speed,
        'reversed': reversed,
        'volume': volume,
        'fadeIn': fadeIn,
        'fadeOut': fadeOut,
        'colorAdjust': colorAdjust.toJson(),
      };

  factory TimelineClip.fromJson(Map<String, dynamic> json) => TimelineClip(
        id: json['id'] as String,
        mediaPath: json['mediaPath'] as String,
        start: (json['start'] as num).toDouble(),
        duration: (json['duration'] as num).toDouble(),
        sourceStart: (json['sourceStart'] as num? ?? 0).toDouble(),
        speed: (json['speed'] as num? ?? 1.0).toDouble(),
        reversed: json['reversed'] as bool? ?? false,
        volume: (json['volume'] as num? ?? 1.0).toDouble(),
        fadeIn: (json['fadeIn'] as num? ?? 0).toDouble(),
        fadeOut: (json['fadeOut'] as num? ?? 0).toDouble(),
        colorAdjust: json['colorAdjust'] == null
            ? ColorAdjust.identity
            : ColorAdjust.fromJson(
                Map<String, dynamic>.from(json['colorAdjust'] as Map)),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineClip &&
          id == other.id &&
          mediaPath == other.mediaPath &&
          start == other.start &&
          duration == other.duration &&
          sourceStart == other.sourceStart &&
          speed == other.speed &&
          reversed == other.reversed &&
          volume == other.volume &&
          fadeIn == other.fadeIn &&
          fadeOut == other.fadeOut &&
          colorAdjust == other.colorAdjust;

  @override
  int get hashCode => Object.hash(
        id,
        mediaPath,
        start,
        duration,
        sourceStart,
        speed,
        reversed,
        volume,
        fadeIn,
        fadeOut,
        colorAdjust,
      );
}

/// One lane of the timeline.
class TimelineTrack {
  final String id;
  final TrackType type;
  final List<TimelineClip> clips;

  const TimelineTrack({
    required this.id,
    required this.type,
    this.clips = const [],
  });

  double get end {
    var maxEnd = 0.0;
    for (final clip in clips) {
      if (clip.end > maxEnd) maxEnd = clip.end;
    }
    return maxEnd;
  }

  TimelineTrack copyWith({
    String? id,
    TrackType? type,
    List<TimelineClip>? clips,
  }) {
    return TimelineTrack(
      id: id ?? this.id,
      type: type ?? this.type,
      clips: clips ?? this.clips,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'clips': clips.map((c) => c.toJson()).toList(),
      };

  factory TimelineTrack.fromJson(Map<String, dynamic> json) => TimelineTrack(
        id: json['id'] as String,
        type: TrackType.values.byName(json['type'] as String),
        clips: (json['clips'] as List? ?? const [])
            .map((e) =>
                TimelineClip.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineTrack &&
          id == other.id &&
          type == other.type &&
          _listEquals(clips, other.clips);

  @override
  int get hashCode => Object.hash(id, type, Object.hashAll(clips));
}

/// The editable timeline of a project.
class TimelineProject {
  final List<TimelineTrack> tracks;
  final List<TextOverlay> textOverlays;

  const TimelineProject({
    this.tracks = const [],
    this.textOverlays = const [],
  });

  /// Max over clips of start+duration, minimum 1.0s.
  double get duration {
    var maxEnd = 0.0;
    for (final track in tracks) {
      final trackEnd = track.end;
      if (trackEnd > maxEnd) maxEnd = trackEnd;
    }
    return maxEnd < 1.0 ? 1.0 : maxEnd;
  }

  TimelineProject copyWith({
    List<TimelineTrack>? tracks,
    List<TextOverlay>? textOverlays,
  }) {
    return TimelineProject(
      tracks: tracks ?? this.tracks,
      textOverlays: textOverlays ?? this.textOverlays,
    );
  }

  Map<String, dynamic> toJson() => {
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'textOverlays': textOverlays.map((t) => t.toJson()).toList(),
      };

  factory TimelineProject.fromJson(Map<String, dynamic> json) =>
      TimelineProject(
        tracks: (json['tracks'] as List? ?? const [])
            .map((e) =>
                TimelineTrack.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        textOverlays: (json['textOverlays'] as List? ?? const [])
            .map((e) =>
                TextOverlay.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineProject &&
          _listEquals(tracks, other.tracks) &&
          _listEquals(textOverlays, other.textOverlays);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(tracks),
        Object.hashAll(textOverlays),
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
