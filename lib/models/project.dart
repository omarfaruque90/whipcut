import 'package:whipcut/models/timeline.dart';

/// Aspect ratio presets available when creating a project.
///
/// Owned by Agent B (projects/data). The [ratio] drives the preview frame
/// geometry; [label] is what users see in chips and project cards.
enum AspectRatioPreset { r16x9, r9x16, r1x1, r4x5 }

/// Helpers for [AspectRatioPreset].
extension AspectRatioPresetX on AspectRatioPreset {
  /// Width / height as a plain double.
  double get ratio => switch (this) {
        AspectRatioPreset.r16x9 => 16 / 9,
        AspectRatioPreset.r9x16 => 9 / 16,
        AspectRatioPreset.r1x1 => 1,
        AspectRatioPreset.r4x5 => 4 / 5,
      };

  /// Display label, e.g. "16:9".
  String get label => switch (this) {
        AspectRatioPreset.r16x9 => '16:9',
        AspectRatioPreset.r9x16 => '9:16',
        AspectRatioPreset.r1x1 => '1:1',
        AspectRatioPreset.r4x5 => '4:5',
      };
}

/// A saved Whipcut video project.
///
/// Owned by Agent B (projects/data). Serialized by hand to
/// `whipcut_projects/<id>.json` in the app documents directory via
/// [ProjectRepository]. The timeline itself is owned by Agent C.
class WhipcutProject {
  const WhipcutProject({
    required this.id,
    required this.name,
    required this.aspectRatio,
    required this.createdAt,
    required this.updatedAt,
    required this.timeline,
  });

  final String id;
  final String name;
  final AspectRatioPreset aspectRatio;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The clip/text timeline. Owned by Agent C — see models/timeline.dart.
  final TimelineProject timeline;

  WhipcutProject copyWith({
    String? id,
    String? name,
    AspectRatioPreset? aspectRatio,
    DateTime? createdAt,
    DateTime? updatedAt,
    TimelineProject? timeline,
  }) {
    return WhipcutProject(
      id: id ?? this.id,
      name: name ?? this.name,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      timeline: timeline ?? this.timeline,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'aspectRatio': aspectRatio.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'timeline': timeline.toJson(),
    };
  }

  factory WhipcutProject.fromJson(Map<String, dynamic> json) {
    return WhipcutProject(
      id: json['id'] as String,
      name: json['name'] as String,
      aspectRatio: AspectRatioPreset.values.byName(json['aspectRatio'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      timeline: TimelineProject.fromJson(json['timeline'] as Map<String, dynamic>),
    );
  }
}
