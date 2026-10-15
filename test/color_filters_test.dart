// Unit tests for one-tap color filter presets (Agent F).
//
// Covers: preset catalog sanity, ColorAdjust model extension
// (lift/tealOrange, backward-compatible JSON), preview-matrix math, and
// the preset -> ffmpeg export mapping via the pure command builder.
import 'package:flutter_test/flutter_test.dart';
import 'package:whipcut/features/export/export_engine.dart';
import 'package:whipcut/features/filters/color_filters.dart';
import 'package:whipcut/models/color_adjust.dart';
import 'package:whipcut/models/timeline.dart';

TimelineClip _clip({ColorAdjust colorAdjust = ColorAdjust.identity}) =>
    TimelineClip(
      id: 'c1',
      mediaPath: '/sdcard/vid.mp4',
      start: 0,
      duration: 4,
      sourceStart: 0,
      speed: 1,
      reversed: false,
      volume: 1,
      fadeIn: 0,
      fadeOut: 0,
      colorAdjust: colorAdjust,
    );

String _cmd(ColorAdjust adjust) {
  final plan = ExportPlan(
    videoClips: [PlannedVideoClip(clip: _clip(colorAdjust: adjust), hasAudio: false)],
    audioClips: const [],
    textOverlays: const [],
    totalDuration: 4,
  );
  return buildArguments(plan, ExportSettings.youtube4k(), '/out/x.mp4')
      .join(' ');
}

void main() {
  group('preset catalog', () {
    test('has at least 10 distinct presets with valid ranges', () {
      expect(kBuiltinPresets.length, greaterThanOrEqualTo(10));
      final ids = kBuiltinPresets.map((p) => p.id).toSet();
      expect(ids.length, kBuiltinPresets.length); // unique ids
      for (final p in kBuiltinPresets) {
        expect(p.nameEn.isNotEmpty, true, reason: p.id);
        expect(p.nameBn.isNotEmpty, true, reason: p.id);
        expect(p.thumbColors.length, greaterThanOrEqualTo(2));
        final a = p.adjust;
        expect(a.exposure, inInclusiveRange(-2.0, 2.0));
        expect(a.contrast, inInclusiveRange(0.0, 2.0));
        expect(a.saturation, inInclusiveRange(0.0, 2.0));
        expect(a.temperature, inInclusiveRange(-1.0, 1.0));
        expect(a.lift, inInclusiveRange(0.0, 0.5));
        expect(a.tealOrange, inInclusiveRange(0.0, 1.0));
        expect(a.lutPath, isNull);
      }
    });

    test('cinematic look uses the teal-orange grade + lifted blacks', () {
      final cinematic =
          kBuiltinPresets.firstWhere((p) => p.id == 'cinematic');
      expect(cinematic.adjust.tealOrange, greaterThan(0));
      expect(cinematic.adjust.lift, greaterThan(0));
    });

    test('classic B&W is fully desaturated', () {
      final bw = kBuiltinPresets.firstWhere((p) => p.id == 'classicbw');
      expect(bw.adjust.saturation, 0);
    });

    test('preset.matches detects its own look', () {
      final vivid = kBuiltinPresets.firstWhere((p) => p.id == 'vivid4k');
      expect(vivid.matches(vivid.adjust), true);
      expect(vivid.matches(ColorAdjust.identity), false);
    });
  });

  group('ColorAdjust model extension', () {
    test('fromJson is backward compatible with old payloads', () {
      final old = {
        'exposure': 0.5,
        'contrast': 1.2,
        'saturation': 1.0,
        'temperature': 0.0,
      };
      final a = ColorAdjust.fromJson(old);
      expect(a.lift, 0);
      expect(a.tealOrange, 0);
      expect(a.exposure, 0.5);
    });

    test('round-trips the new fields', () {
      const a = ColorAdjust(lift: 0.12, tealOrange: 0.8);
      final b = ColorAdjust.fromJson(a.toJson());
      expect(b, a);
    });
  });

  group('preview matrix', () {
    test('identity adjust yields the identity matrix', () {
      final m = colorMatrixFor(ColorAdjust.identity);
      const expected = [
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0, //
      ];
      for (var i = 0; i < 20; i++) {
        expect(m[i], closeTo(expected[i], 1e-9));
      }
    });

    test('B&W preset maps pure red to gray', () {
      final bw = kBuiltinPresets.firstWhere((p) => p.id == 'classicbw');
      final m = colorMatrixFor(bw.adjust);
      // r' = m[0]*1, g' = m[5]*1, b' = m[10]*1 for pure red input.
      final r = m[0], g = m[5], b = m[10];
      expect(r, closeTo(g, 1e-9));
      expect(g, closeTo(b, 1e-9));
      expect(r, closeTo(0.213 * 1.1, 1e-6)); // luma * contrast
    });

    test('warm preset adds a red offset', () {
      final warm = kBuiltinPresets.firstWhere((p) => p.id == 'warmsunset');
      final m = colorMatrixFor(warm.adjust);
      expect(m[4], greaterThan(0)); // red channel offset
      expect(m[14], lessThan(0)); // blue channel offset
    });
  });

  group('preset -> ffmpeg export mapping', () {
    test('lift emits a curves filter', () {
      final cmd = _cmd(const ColorAdjust(lift: 0.12));
      expect(cmd, contains("curves=all='0/0.12 1/1'"));
    });

    test('tealOrange emits a colorbalance filter', () {
      final cmd = _cmd(const ColorAdjust(tealOrange: 0.8));
      expect(cmd, contains('colorbalance='));
      expect(cmd, contains('bs=0.24'));
      expect(cmd, contains('rh=0.16'));
    });

    test('neutral adjust emits no color filters', () {
      final cmd = _cmd(ColorAdjust.identity);
      expect(cmd, isNot(contains('curves=')));
      expect(cmd, isNot(contains('colorbalance=')));
      expect(cmd, isNot(contains('eq=')));
      expect(cmd, isNot(contains('colortemperature=')));
    });

    test('cinematic preset renders its full grade chain', () {
      final cinematic =
          kBuiltinPresets.firstWhere((p) => p.id == 'cinematic');
      final cmd = _cmd(cinematic.adjust);
      expect(cmd, contains('eq='));
      expect(cmd, contains('colorbalance='));
      expect(cmd, contains('curves='));
    });
  });

  group('custom presets', () {
    test('JSON round-trip', () {
      const p = CustomFilterPreset(
        id: 'custom_1',
        name: 'My Look',
        adjust: ColorAdjust(contrast: 1.3, saturation: 0.9),
      );
      final q = CustomFilterPreset.fromJson(p.toJson());
      expect(q.id, 'custom_1');
      expect(q.name, 'My Look');
      expect(q.adjust, p.adjust);
    });
  });
}
