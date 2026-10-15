/// Per-clip color/adjust model.
///
/// Owned by Agent D1 (Color/Adjust panel).
///
/// Sliders in [AdjustScreen] edit this model live and it is persisted with the
/// project via [WhipcutProject] JSON. Actual pixel filtering is NOT rendered
/// in the preview — it happens at export time (ffmpeg `eq` / `lut3d`
/// filters, owned by the export agent).
class ColorAdjust {
  /// Exposure compensation in EV. Range -2.0..2.0.
  final double exposure;

  /// Contrast multiplier. Range 0..2.
  final double contrast;

  /// Saturation multiplier. Range 0..2.
  final double saturation;

  /// White-balance temperature shift. Range -1..1 (cool..warm).
  final double temperature;

  /// Absolute path to an imported `.cube` LUT file, or null for none.
  final String? lutPath;

  const ColorAdjust({
    this.exposure = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.temperature = 0,
    this.lutPath,
  });

  /// Neutral adjustments — no visible change.
  static const ColorAdjust identity = ColorAdjust();

  /// Sentinel so `copyWith(lutPath: null)` explicitly clears the LUT while
  /// omitting `lutPath` keeps the current value.
  static const _unset = Object();

  ColorAdjust copyWith({
    double? exposure,
    double? contrast,
    double? saturation,
    double? temperature,
    Object? lutPath = _unset,
  }) {
    return ColorAdjust(
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      temperature: temperature ?? this.temperature,
      lutPath: identical(lutPath, _unset) ? this.lutPath : lutPath as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'exposure': exposure,
      'contrast': contrast,
      'saturation': saturation,
      'temperature': temperature,
      'lutPath': lutPath,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorAdjust &&
          exposure == other.exposure &&
          contrast == other.contrast &&
          saturation == other.saturation &&
          temperature == other.temperature &&
          lutPath == other.lutPath;

  @override
  int get hashCode =>
      Object.hash(exposure, contrast, saturation, temperature, lutPath);

  factory ColorAdjust.fromJson(Map<String, dynamic> json) {
    double numOr(String key, double fallback) {
      final value = json[key];
      return value is num ? value.toDouble() : fallback;
    }

    return ColorAdjust(
      exposure: numOr('exposure', 0),
      contrast: numOr('contrast', 1),
      saturation: numOr('saturation', 1),
      temperature: numOr('temperature', 0),
      lutPath: json['lutPath'] as String?,
    );
  }
}
