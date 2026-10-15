import 'package:image/image.dart' as img;

/// "Match from Photo" color transfer (Agent — photo match).
///
/// Pure math, no Flutter dependencies, so it is unit-testable:
///  1. [channelHistograms] builds a 256-bin per-channel (R/G/B) histogram.
///  2. [histogramMatch] maps the *source* (video frame) levels onto the
///     *reference* (picked photo) levels by CDF matching — the classic
///     Photoshop/PicsArt-style "match color" operation.
///  3. [photoCurvesFilter] quantizes the mapping to 17 sample points and
///     emits an ffmpeg `curves` filter string, stored on
///     [ColorAdjust.photoCurves] and baked at export.

/// Number of histogram bins per channel.
const int kHistogramBins = 256;

/// Sample points used to quantize a 256-level mapping for the ffmpeg
/// `curves` filter: 0, 16, 32, ..., 240, 255.
const List<int> kCurveSamplePoints = [
  0, 16, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224, 240, 255
];

/// Builds per-channel histograms: index 0 = R, 1 = G, 2 = B, each 256 bins.
///
/// The image is expected to be pre-scaled (the service downsamples to
/// <= 512px on the long edge); callers may pass any size.
List<List<int>> channelHistograms(img.Image image) {
  final hists =
      List.generate(3, (_) => List<int>.filled(kHistogramBins, 0));
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      hists[0][pixel.r.toInt().clamp(0, 255)]++;
      hists[1][pixel.g.toInt().clamp(0, 255)]++;
      hists[2][pixel.b.toInt().clamp(0, 255)]++;
    }
  }
  return hists;
}

/// CDF-based histogram matching.
///
/// Returns `mapping[c][v]`: the reference level that source level `v`
/// should become on channel `c`. For each source level, finds the smallest
/// reference level whose CDF is >= the source level's CDF. Levels with no
/// source mass map toward 0, which keeps the mapping total and safe for
/// empty histograms (identity fallback).
List<List<int>> histogramMatch(
  List<List<int>> source,
  List<List<int>> reference,
) {
  final mapping =
      List.generate(3, (_) => List<int>.filled(kHistogramBins, 0));
  for (var c = 0; c < 3; c++) {
    final srcCdf = _cdf(source[c]);
    final refCdf = _cdf(reference[c]);
    var r = 0;
    for (var v = 0; v < kHistogramBins; v++) {
      // Empty source histogram -> identity mapping.
      if (srcCdf[kHistogramBins - 1] <= 0) {
        mapping[c][v] = v;
        continue;
      }
      while (r < kHistogramBins - 1 && refCdf[r] < srcCdf[v]) {
        r++;
      }
      mapping[c][v] = r;
    }
  }
  return mapping;
}

List<double> _cdf(List<int> hist) {
  final total = hist.fold<int>(0, (a, b) => a + b);
  final cdf = List<double>.filled(kHistogramBins, 0);
  if (total <= 0) return cdf;
  var acc = 0;
  for (var i = 0; i < kHistogramBins; i++) {
    acc += hist[i];
    cdf[i] = acc / total;
  }
  return cdf;
}

/// Formats a 0..1 double with 3 decimals for ffmpeg filter args.
String _f(double v) {
  if (v.isNaN || v.isInfinite) return '0.000';
  return v.clamp(0.0, 1.0).toStringAsFixed(3);
}

/// Converts a 3x256 [mapping] into an ffmpeg filter string:
///
/// `curves=r='0/0.000 16/0.063 ... 255/1.000':g='...':b='...'`
///
/// The mapping is quantized to [kCurveSamplePoints]; ffmpeg interpolates
/// between points. This exact string is stored on
/// `ColorAdjust.photoCurves` and appended to the export filter chain.
String photoCurvesFilter(List<List<int>> mapping) {
  const names = ['r', 'g', 'b'];
  final parts = <String>[];
  for (var c = 0; c < 3; c++) {
    final points = <String>[];
    for (final level in kCurveSamplePoints) {
      final out = mapping[c][level.clamp(0, 255)];
      points.add('$level/${_f(out / 255.0)}');
    }
    parts.add("${names[c]}='${points.join(' ')}'");
  }
  return "curves=${parts.join(':')}";
}

/// Linear least-squares fit of one channel's curve, for the in-app
/// preview approximation: returns `[slope, intercept]` in normalized
/// 0..1 space, i.e. out ≈ slope * in + intercept.
///
/// Parses the string produced by [photoCurvesFilter]; returns `[1.0, 0.0]`
/// (identity) when parsing fails so the preview never breaks.
List<double> linearFitForChannel(String curvesFilter, int channel) {
  try {
    const names = ['r', 'g', 'b'];
    final re = RegExp("${names[channel]}='([^']*)'");
    final match = re.firstMatch(curvesFilter);
    if (match == null) return const [1.0, 0.0];
    final pts = <double>[];
    for (final token in match.group(1)!.split(' ')) {
      final xy = token.split('/');
      if (xy.length != 2) continue;
      final x = double.tryParse(xy[0]);
      final y = double.tryParse(xy[1]);
      if (x == null || y == null) continue;
      pts.add(x / 255.0);
      pts.add(y);
    }
    if (pts.length < 4) return const [1.0, 0.0];
    // Least squares: y = a*x + b over (x, y) pairs.
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    final n = pts.length ~/ 2;
    for (var i = 0; i < n; i++) {
      final x = pts[i * 2], y = pts[i * 2 + 1];
      sx += x;
      sy += y;
      sxx += x * x;
      sxy += x * y;
    }
    final denom = n * sxx - sx * sx;
    if (denom.abs() < 1e-9) return const [1.0, 0.0];
    final a = (n * sxy - sx * sy) / denom;
    final b = (sy - a * sx) / n;
    return [a, b];
  } catch (_) {
    return const [1.0, 0.0];
  }
}
