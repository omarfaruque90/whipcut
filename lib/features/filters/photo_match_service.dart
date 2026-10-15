import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'photo_match.dart';

/// Orchestrates "Match from Photo": pick a reference photo, extract a
/// representative video frame, histogram-match the photo's grade onto the
/// frame, and return an ffmpeg `curves` filter string for the export.
///
/// Everything runs on-device; no server involved. Errors are returned as
/// [PhotoMatchError] codes so the UI can show localized messages.
class PhotoMatchService {
  PhotoMatchService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Runs the full flow. Returns the curves filter string on success.
  ///
  /// [videoPath] is the selected clip's media file; [clipDuration] is used
  /// to pick the middle frame (falls back to 0.5s when unknown).
  Future<PhotoMatchResult> match({
    required String videoPath,
    required double clipDuration,
  }) async {
    // 1. Pick the reference photo.
    final picked =
        await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return const PhotoMatchResult.cancelled();

    // 2. Decode the photo.
    final refBytes = await picked.readAsBytes();
    final refImage = img.decodeImage(refBytes);
    if (refImage == null) {
      return const PhotoMatchResult.error(PhotoMatchError.unreadableImage);
    }
    if (refImage.width < 16 || refImage.height < 16) {
      return const PhotoMatchResult.error(PhotoMatchError.imageTooSmall);
    }

    // 3. Extract a representative frame from the middle of the clip.
    final frameFile = await _extractFrame(videoPath, clipDuration);
    if (frameFile == null) {
      return const PhotoMatchResult.error(PhotoMatchError.frameFailed);
    }
    final frameImage = img.decodeImage(await frameFile.readAsBytes());
    // Clean up the temp frame right away.
    try {
      await frameFile.delete();
    } catch (_) {}
    if (frameImage == null) {
      return const PhotoMatchResult.error(PhotoMatchError.frameFailed);
    }

    // 4. Downscale for speed (statistically equivalent histograms).
    final ref = _downscale(refImage);
    final frame = _downscale(frameImage);

    // 5. Match + build the ffmpeg filter string.
    final mapping = histogramMatch(
      channelHistograms(frame),
      channelHistograms(ref),
    );
    return PhotoMatchResult.ok(photoCurvesFilter(mapping));
  }

  /// Downscales so the long edge is at most 512px.
  img.Image _downscale(img.Image image) {
    const maxEdge = 512;
    final longEdge =
        image.width > image.height ? image.width : image.height;
    if (longEdge <= maxEdge) return image;
    if (image.width >= image.height) {
      return img.copyResize(image, width: maxEdge);
    }
    return img.copyResize(image, height: maxEdge);
  }

  /// Extracts one JPEG frame near the middle of [videoPath].
  /// Returns the temp file, or null on failure.
  Future<File?> _extractFrame(String videoPath, double clipDuration) async {
    try {
      final dir = await getTemporaryDirectory();
      final out = File(
          '${dir.path}/whipcut_match_frame_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final at = clipDuration > 0 ? (clipDuration / 2) : 0.5;
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-ss',
        at.toStringAsFixed(2),
        '-i',
        videoPath,
        '-frames:v',
        '1',
        '-q:v',
        '2',
        out.path,
      ]);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && await out.exists()) return out;
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// Probes a video file's duration in seconds (0 when unknown).
Future<double> probeVideoDurationSeconds(String videoPath) async {
  try {
    final session = await FFprobeKit.getMediaInformation(videoPath);
    final info = session.getMediaInformation();
    final raw = info?.getDuration();
    final d = double.tryParse(raw ?? '');
    if (d != null && d > 0) return d;
  } catch (_) {}
  return 0;
}

/// User-facing failure reasons for the photo-match flow.
enum PhotoMatchError {
  /// No video clip available to match against.
  noVideo,

  /// The picked image could not be decoded.
  unreadableImage,

  /// The picked image is too small to analyze.
  imageTooSmall,

  /// A representative frame could not be extracted from the video.
  frameFailed,
}

/// Outcome of [PhotoMatchService.match].
class PhotoMatchResult {
  const PhotoMatchResult._({
    this.curves,
    this.error,
    this.cancelled = false,
  });

  const PhotoMatchResult.ok(String curves)
      : this._(curves: curves);

  const PhotoMatchResult.error(PhotoMatchError error)
      : this._(error: error);

  const PhotoMatchResult.cancelled() : this._(cancelled: true);

  /// The ffmpeg `curves=...` filter string, when successful.
  final String? curves;

  /// Why the flow failed, when it did.
  final PhotoMatchError? error;

  /// True when the user dismissed the image picker.
  final bool cancelled;

  bool get isOk => curves != null && curves!.isNotEmpty;
}
