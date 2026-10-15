import 'package:uuid/uuid.dart';

/// A text overlay placed on the video timeline.
///
/// Position is stored as relative coordinates (0..1) so overlays scale with
/// any aspect ratio. Burned into the video at export via ffmpeg `drawtext`.
class TextOverlay {
  /// Stable id, generated with [Uuid.v4].
  final String id;

  /// The visible text.
  final String text;

  /// Font size in logical px. Defaults to 48.
  final double fontSize;

  /// Text color as an ARGB int (e.g. `0xFFFFFFFF`). Defaults to white.
  final int color;

  /// Horizontal position, 0 (left) .. 1 (right). Defaults to 0.5 (center).
  final double x;

  /// Vertical position, 0 (top) .. 1 (bottom). Defaults to 0.5 (center).
  final double y;

  /// When the overlay appears on the timeline, in seconds.
  final double start;

  /// How long the overlay stays visible, in seconds.
  final double duration;

  /// Render the text bold.
  final bool bold;

  const TextOverlay({
    required this.id,
    required this.text,
    this.fontSize = 48,
    this.color = 0xFFFFFFFF,
    this.x = 0.5,
    this.y = 0.5,
    this.start = 0,
    this.duration = 2,
    this.bold = false,
  });

  /// Convenience factory that assigns a fresh uuid.
  factory TextOverlay.create({
    required String text,
    double fontSize = 48,
    int color = 0xFFFFFFFF,
    double x = 0.5,
    double y = 0.5,
    double start = 0,
    double duration = 2,
    bool bold = false,
  }) =>
      TextOverlay(
        id: const Uuid().v4(),
        text: text,
        fontSize: fontSize,
        color: color,
        x: x,
        y: y,
        start: start,
        duration: duration,
        bold: bold,
      );

  TextOverlay copyWith({
    String? id,
    String? text,
    double? fontSize,
    int? color,
    double? x,
    double? y,
    double? start,
    double? duration,
    bool? bold,
  }) =>
      TextOverlay(
        id: id ?? this.id,
        text: text ?? this.text,
        fontSize: fontSize ?? this.fontSize,
        color: color ?? this.color,
        x: x ?? this.x,
        y: y ?? this.y,
        start: start ?? this.start,
        duration: duration ?? this.duration,
        bold: bold ?? this.bold,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'fontSize': fontSize,
        'color': color,
        'x': x,
        'y': y,
        'start': start,
        'duration': duration,
        'bold': bold,
      };

  factory TextOverlay.fromJson(Map<String, dynamic> json) => TextOverlay(
        id: json['id'] as String,
        text: json['text'] as String,
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 48,
        color: (json['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
        x: (json['x'] as num?)?.toDouble() ?? 0.5,
        y: (json['y'] as num?)?.toDouble() ?? 0.5,
        start: (json['start'] as num?)?.toDouble() ?? 0,
        duration: (json['duration'] as num?)?.toDouble() ?? 2,
        bold: json['bold'] as bool? ?? false,
      );
}
