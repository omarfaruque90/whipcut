import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whipcut/models/color_adjust.dart';

import 'photo_match.dart';

/// One-tap color filter presets (Agent F).
///
/// A preset is a named [ColorAdjust] bundle: tapping a card writes the
/// bundle into the selected clip's `colorAdjust`, and the export engine
/// bakes the exact same values via ffmpeg (`eq` / `colortemperature` /
/// `curves` / `colorbalance`). The in-app preview is only an approximation
/// (see [colorMatrixFor]) — the export is authoritative.

/// A built-in one-tap filter preset.
class ColorFilterPreset {
  const ColorFilterPreset({
    required this.id,
    required this.nameEn,
    required this.nameBn,
    required this.adjust,
    required this.thumbColors,
  });

  final String id;
  final String nameEn;
  final String nameBn;
  final ColorAdjust adjust;

  /// 2-3 representative colors for the gallery thumbnail gradient.
  final List<Color> thumbColors;

  String nameFor(String languageCode) =>
      languageCode == 'bn' ? nameBn : nameEn;

  /// True when [adjust] matches this preset's look (LUT aside).
  bool matches(ColorAdjust other) =>
      _eq(adjust.exposure, other.exposure) &&
      _eq(adjust.contrast, other.contrast) &&
      _eq(adjust.saturation, other.saturation) &&
      _eq(adjust.temperature, other.temperature) &&
      _eq(adjust.lift, other.lift) &&
      _eq(adjust.tealOrange, other.tealOrange) &&
      adjust.photoCurves == other.photoCurves;

  static bool _eq(double a, double b) => (a - b).abs() < 1e-6;
}

/// A user-saved preset ("Save as preset" from the sliders).
class CustomFilterPreset {
  const CustomFilterPreset({
    required this.id,
    required this.name,
    required this.adjust,
  });

  final String id;
  final String name;
  final ColorAdjust adjust;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'adjust': adjust.toJson()};

  factory CustomFilterPreset.fromJson(Map<String, dynamic> json) {
    final adjustJson = json['adjust'];
    return CustomFilterPreset(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      adjust: adjustJson is Map
          ? ColorAdjust.fromJson(Map<String, dynamic>.from(adjustJson))
          : ColorAdjust.identity,
    );
  }
}

/// The built-in one-tap looks. At least 10, each a distinct mood.
const List<ColorFilterPreset> kBuiltinPresets = [
  ColorFilterPreset(
    id: 'enhance',
    nameEn: 'Enhance',
    nameBn: 'এনহ্যান্স',
    adjust: ColorAdjust(exposure: 0.15, contrast: 1.08, saturation: 1.15),
    thumbColors: [Color(0xFF7FB3FF), Color(0xFFFFB37F)],
  ),
  ColorFilterPreset(
    id: 'cinematic',
    nameEn: 'Cinematic',
    nameBn: 'সিনেমাটিক',
    adjust: ColorAdjust(
        contrast: 1.12, saturation: 0.92, tealOrange: 0.8, lift: 0.06),
    thumbColors: [Color(0xFF1F6F8B), Color(0xFFE08E45)],
  ),
  ColorFilterPreset(
    id: 'vivid4k',
    nameEn: 'Vivid 4K',
    nameBn: 'ভিভিড 4K',
    adjust: ColorAdjust(exposure: 0.1, contrast: 1.2, saturation: 1.4),
    thumbColors: [Color(0xFF00C853), Color(0xFFFF3D00)],
  ),
  ColorFilterPreset(
    id: 'vintage',
    nameEn: 'Vintage Film',
    nameBn: 'ভিনটেজ ফিল্ম',
    adjust: ColorAdjust(
        temperature: 0.35, saturation: 0.75, contrast: 0.92, lift: 0.12),
    thumbColors: [Color(0xFFD2A679), Color(0xFF8B5E34)],
  ),
  ColorFilterPreset(
    id: 'classicbw',
    nameEn: 'Classic B&W',
    nameBn: 'সাদা-কালো',
    adjust: ColorAdjust(saturation: 0, contrast: 1.1),
    thumbColors: [Color(0xFF9E9E9E), Color(0xFF212121)],
  ),
  ColorFilterPreset(
    id: 'warmsunset',
    nameEn: 'Warm Sunset',
    nameBn: 'ওয়ার্ম সানসেট',
    adjust: ColorAdjust(temperature: 0.6, saturation: 1.25, exposure: 0.1),
    thumbColors: [Color(0xFFFFB300), Color(0xFFFF5722)],
  ),
  ColorFilterPreset(
    id: 'coldblue',
    nameEn: 'Cold Blue',
    nameBn: 'কোল্ড ব্লু',
    adjust: ColorAdjust(temperature: -0.6, saturation: 1.1, contrast: 1.05),
    thumbColors: [Color(0xFF90CAF9), Color(0xFF0D47A1)],
  ),
  ColorFilterPreset(
    id: 'noir',
    nameEn: 'Noir',
    nameBn: 'নোয়ার',
    adjust: ColorAdjust(saturation: 0, contrast: 1.45, lift: 0.03),
    thumbColors: [Color(0xFFE0E0E0), Color(0xFF000000)],
  ),
  ColorFilterPreset(
    id: 'pastel',
    nameEn: 'Pastel',
    nameBn: 'প্যাস্টেল',
    adjust: ColorAdjust(
        saturation: 0.8, contrast: 0.9, lift: 0.08, exposure: 0.15),
    thumbColors: [Color(0xFFF8BBD0), Color(0xFFB3E5FC)],
  ),
  ColorFilterPreset(
    id: 'moody',
    nameEn: 'Moody',
    nameBn: 'মুডি',
    adjust: ColorAdjust(
        contrast: 1.25, saturation: 0.85, tealOrange: 0.4, exposure: -0.1),
    thumbColors: [Color(0xFF37474F), Color(0xFFFF8A65)],
  ),
  ColorFilterPreset(
    id: 'golden',
    nameEn: 'Golden Hour',
    nameBn: 'গোল্ডেন আওয়ার',
    adjust: ColorAdjust(temperature: 0.45, saturation: 1.2, contrast: 1.05),
    thumbColors: [Color(0xFFFFD54F), Color(0xFFFF6F00)],
  ),
];

// Custom presets -------------------------------------------------------------

const _kCustomPresetsKey = 'whipcut_custom_color_presets';

Future<List<CustomFilterPreset>> loadCustomPresets() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kCustomPresetsKey);
  if (raw == null || raw.isEmpty) return const [];
  final decoded = jsonDecode(raw) as List;
  final out = <CustomFilterPreset>[];
  for (final item in decoded) {
    try {
      final p = CustomFilterPreset.fromJson(
          Map<String, dynamic>.from(item as Map));
      if (p.id.isNotEmpty && p.name.isNotEmpty) out.add(p);
    } catch (_) {
      // Skip corrupt entries.
    }
  }
  return out;
}

/// Saves the current slider look as a named custom preset.
Future<void> saveCustomPreset(String name, ColorAdjust adjust) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = await loadCustomPresets();
  final entry = CustomFilterPreset(
    id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
    name: name.trim(),
    // Custom presets store the color look only; a LUT stays per-clip.
    adjust: adjust.copyWith(lutPath: null),
  );
  existing.add(entry);
  await prefs.setString(
    _kCustomPresetsKey,
    jsonEncode([for (final e in existing) e.toJson()]),
  );
}

Future<void> deleteCustomPreset(String id) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = await loadCustomPresets();
  existing.removeWhere((e) => e.id == id);
  await prefs.setString(
    _kCustomPresetsKey,
    jsonEncode([for (final e in existing) e.toJson()]),
  );
}

// Preview approximation ------------------------------------------------------

/// Builds a 4x5 color matrix (row-major, 20 values) approximating
/// [adjust] for `ColorFiltered`. Approximate — the export's ffmpeg filters
/// are authoritative.
List<double> colorMatrixFor(ColorAdjust adjust) {
  var m = _identity();
  m = _mul(_saturation(adjust.saturation), m);
  m = _mul(_contrast(adjust.contrast), m);
  m = _mul(_brightness(adjust.exposure * 0.15), m);
  m = _mul(_temperature(adjust.temperature), m);
  m = _mul(_tealOrange(adjust.tealOrange), m);
  m = _mul(_lift(adjust.lift), m);
  m = _mul(_photoCurves(adjust.photoCurves), m);
  return m;
}

List<double> _identity() => const [
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0, //
      0, 0, 1, 0, 0, //
      0, 0, 0, 1, 0, //
    ];

/// Composes 4x5 matrices: returns `a` applied after `b`.
List<double> _mul(List<double> a, List<double> b) {
  final c = List<double>.filled(20, 0);
  for (var r = 0; r < 4; r++) {
    for (var col = 0; col < 5; col++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[r * 5 + k] * b[k * 5 + col];
      }
      if (col == 4) sum += a[r * 5 + 4]; // affine offset of `a`
      c[r * 5 + col] = sum;
    }
  }
  return c;
}

List<double> _saturation(double s) {
  const r = 0.213, g = 0.715, b = 0.072;
  final inv = 1 - s;
  return [
    r * inv + s, g * inv, b * inv, 0, 0, //
    r * inv, g * inv + s, b * inv, 0, 0, //
    r * inv, g * inv, b * inv + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> _contrast(double c) {
  final o = 0.5 * (1 - c);
  return [
    c, 0, 0, 0, o, //
    0, c, 0, 0, o, //
    0, 0, c, 0, o, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> _brightness(double b) => [
      1, 0, 0, 0, b, //
      0, 1, 0, 0, b, //
      0, 0, 1, 0, b, //
      0, 0, 0, 1, 0, //
    ];

/// Warm (positive) adds red / removes blue; cool does the reverse.
List<double> _temperature(double t) {
  final r = 0.10 * t;
  final b = -0.10 * t;
  return [
    1, 0, 0, 0, r, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, b, //
    0, 0, 0, 1, 0, //
  ];
}

/// Linear stand-in for the teal-shadows / orange-highlights grade.
List<double> _tealOrange(double t) {
  final r = 0.05 * t;
  final g = 0.025 * t;
  final b = 0.01 * t;
  return [
    1, 0, 0, 0, r, //
    0, 1, 0, 0, g, //
    0, 0, 1, 0, b, //
    0, 0, 0, 1, 0, //
  ];
}

/// Lifted blacks: out = in * (1 - l) + l, matching `curves=all='0/l 1/1'`.
List<double> _lift(double l) {
  final f = 1 - l.clamp(0.0, 0.5);
  return [
    f, 0, 0, 0, l, //
    0, f, 0, 0, l, //
    0, 0, f, 0, l, //
    0, 0, 0, 1, 0, //
  ];
}

/// "Match from Photo" preview approximation: least-squares linear fit of
/// each channel's curve (see [linearFitForChannel]), expressed as a
/// diagonal gain + offset per channel. Approximate — the export's true
/// per-point `curves` filter is authoritative.
List<double> _photoCurves(String? curvesFilter) {
  if (curvesFilter == null || curvesFilter.isEmpty) return _identity();
  final fits = [
    for (var c = 0; c < 3; c++) linearFitForChannel(curvesFilter, c)
  ];
  return [
    fits[0][0], 0, 0, 0, fits[0][1], //
    0, fits[1][0], 0, 0, fits[1][1], //
    0, 0, fits[2][0], 0, fits[2][1], //
    0, 0, 0, 1, 0, //
  ];
}
