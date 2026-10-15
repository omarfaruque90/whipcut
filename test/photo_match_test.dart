import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whipcut/features/filters/photo_match.dart';
import 'package:whipcut/models/color_adjust.dart';

List<List<int>> _deltaHist(int channel, int level) {
  final hists = List.generate(3, (_) => List<int>.filled(256, 0));
  hists[channel][level] = 100;
  return hists;
}

void main() {
  group('channelHistograms', () {
    test('counts per-channel bins on a known image', () {
      final image = img.Image(width: 2, height: 2);
      image.setPixel(0, 0, img.ColorRgb8(10, 20, 30));
      image.setPixel(1, 0, img.ColorRgb8(10, 20, 30));
      image.setPixel(0, 1, img.ColorRgb8(200, 0, 0));
      image.setPixel(1, 1, img.ColorRgb8(0, 0, 255));

      final hists = channelHistograms(image);
      expect(hists[0][10], 2);
      expect(hists[0][200], 1);
      expect(hists[0][0], 1);
      expect(hists[1][20], 2);
      expect(hists[1][0], 2);
      expect(hists[2][30], 2);
      expect(hists[2][0], 1);
      expect(hists[2][255], 1);
      // Total mass per channel is 4 pixels.
      for (var c = 0; c < 3; c++) {
        expect(hists[c].fold<int>(0, (a, b) => a + b), 4);
      }
    });
  });

  group('histogramMatch', () {
    test('maps a concentrated source level to the reference level', () {
      // Source: all mass at level 100. Reference: all mass at 200.
      final src = _deltaHist(0, 100);
      final ref = _deltaHist(0, 200);
      final mapping = histogramMatch(src, ref);
      expect(mapping[0][100], 200);
      // Levels below the source mass map toward 0; above map to 200.
      expect(mapping[0][0], 0);
      expect(mapping[0][255], 200);
      // Untouched channels get identity-ish mapping of their own hists
      // (all mass at 0 for both -> level 0 maps to 0).
      expect(mapping[1][0], 0);
    });

    test('grayscale-like identical hists give identity mapping', () {
      final hists = List.generate(3, (_) => List<int>.filled(256, 0));
      for (var c = 0; c < 3; c++) {
        for (var v = 0; v < 256; v++) {
          hists[c][v] = v; // ramp
        }
      }
      final mapping = histogramMatch(hists, hists);
      for (var c = 0; c < 3; c++) {
        for (var v = 0; v < 256; v++) {
          expect(mapping[c][v], v);
        }
      }
    });

    test('empty source histogram falls back to identity', () {
      final empty = List.generate(3, (_) => List<int>.filled(256, 0));
      final ref = _deltaHist(0, 200);
      final mapping = histogramMatch(empty, ref);
      for (var c = 0; c < 3; c++) {
        for (var v = 0; v < 256; v++) {
          expect(mapping[c][v], v);
        }
      }
    });
  });

  group('photoCurvesFilter', () {
    test('emits 17 quantized points per channel in ffmpeg syntax', () {
      final identity =
          List.generate(3, (c) => List.generate(256, (v) => v));
      final s = photoCurvesFilter(identity);
      expect(s.startsWith("curves=r='"), isTrue);
      expect(s.contains(":g='"), isTrue);
      expect(s.contains(":b='"), isTrue);
      // 17 points -> 16 spaces inside each channel's quotes.
      final rSection = RegExp(r"r='([^']*)'").firstMatch(s)!.group(1)!;
      expect(rSection.split(' ').length, 17);
      expect(rSection.startsWith('0/0.000'), isTrue);
      // 16/255 = 0.0627 -> 0.063
      expect(rSection.split(' ')[1], '16/0.063');
      expect(rSection.endsWith('255/1.000'), isTrue);
    });

    test('shifted mapping produces shifted curve points', () {
      final shifted = List.generate(
          3, (_) => List.generate(256, (v) => (v + 50).clamp(0, 255)));
      final s = photoCurvesFilter(shifted);
      final rSection = RegExp(r"r='([^']*)'").firstMatch(s)!.group(1)!;
      // 0 -> 50/255 = 0.196
      expect(rSection.split(' ')[0], '0/0.196');
      // 240 -> 255/255 = 1.000 (clamped)
      expect(rSection.split(' ')[15], '240/1.000');
    });
  });

  group('linearFitForChannel', () {
    test('identity curve fits to slope ~1, intercept ~0', () {
      final identity =
          List.generate(3, (c) => List.generate(256, (v) => v));
      final s = photoCurvesFilter(identity);
      for (var c = 0; c < 3; c++) {
        final fit = linearFitForChannel(s, c);
        // 3-decimal quantization of the curve points adds tiny noise.
        expect(fit[0], closeTo(1.0, 1e-3));
        expect(fit[1], closeTo(0.0, 1e-3));
      }
    });

    test('scaled curve fits to the scale factor', () {
      // No clamping: pure 0.8x scale.
      final scaled = List.generate(
          3, (_) => List.generate(256, (v) => (v * 0.8).round()));
      final s = photoCurvesFilter(scaled);
      final fit = linearFitForChannel(s, 0);
      expect(fit[0], closeTo(0.8, 0.02));
      expect(fit[1], closeTo(0.0, 0.02));
    });

    test('garbage input falls back to identity', () {
      final fit = linearFitForChannel('not-a-curve', 0);
      expect(fit, [1.0, 0.0]);
    });
  });

  group('ColorAdjust photoCurves', () {
    test('JSON round-trip preserves photoCurves', () {
      const adjust = ColorAdjust(photoCurves: "curves=r='0/0.000 255/1.000'");
      final restored =
          ColorAdjust.fromJson(Map<String, dynamic>.from(adjust.toJson()));
      expect(restored.photoCurves, adjust.photoCurves);
      expect(restored, adjust);
    });

    test('old project JSON without the key stays backward-compatible', () {
      final restored = ColorAdjust.fromJson({
        'exposure': 0.1,
        'contrast': 1.0,
        'saturation': 1.0,
        'temperature': 0.0,
        'lift': 0.0,
        'tealOrange': 0.0,
        'lutPath': null,
      });
      expect(restored.photoCurves, isNull);
    });

    test('copyWith can set and clear photoCurves', () {
      const base = ColorAdjust();
      final set = base.copyWith(photoCurves: 'curves=r=...');
      expect(set.photoCurves, 'curves=r=...');
      final cleared = set.copyWith(photoCurves: null);
      expect(cleared.photoCurves, isNull);
      // Omitting keeps the current value.
      expect(set.copyWith().photoCurves, 'curves=r=...');
    });
  });
}
