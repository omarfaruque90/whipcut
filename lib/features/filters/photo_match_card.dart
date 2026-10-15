import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whipcut/core/locale_provider.dart';
import 'package:whipcut/core/theme.dart';
import 'package:whipcut/models/color_adjust.dart';

import 'photo_match_service.dart';

/// "Match from Photo" card for the Filters gallery.
///
/// Lets the user pick any photo (e.g. a preset pic downloaded from a
/// browser) and applies its color grade to the selected clip via
/// histogram matching — the Photoshop/PicsArt-style "match color".
/// Everything runs on-device.
class PhotoMatchCard extends ConsumerWidget {
  const PhotoMatchCard({
    super.key,
    required this.videoPath,
    required this.clipDuration,
    required this.currentAdjust,
    required this.onApply,
  });

  /// Media path of the selected clip, or null when there is no clip.
  final String? videoPath;

  /// Duration of the selected clip in seconds (0 = unknown).
  final double clipDuration;

  /// The selected clip's current adjustments (LUT is preserved).
  final ColorAdjust currentAdjust;

  /// Writes the matched look into the selected clip.
  final ValueChanged<ColorAdjust> onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isBn = ref.watch(localeProvider).languageCode == 'bn';
    final hasPhotoCurves = (currentAdjust.photoCurves?.isNotEmpty ?? false);

    return GestureDetector(
      onTap: () => _run(context, isBn),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF3A2E12), Color(0xFFF5A623)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: hasPhotoCurves
                      ? WhipcutTheme.amber
                      : WhipcutTheme.surfaceOutline,
                  width: hasPhotoCurves ? 2.5 : 1,
                ),
              ),
              child: Center(
                child: hasPhotoCurves
                    ? const Icon(Icons.check_circle,
                        color: WhipcutTheme.amber, size: 28)
                    : const Icon(Icons.photo_camera_outlined,
                        color: Colors.white, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isBn ? 'ছবি থেকে ম্যাচ' : 'Match photo',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: hasPhotoCurves
                  ? WhipcutTheme.amber
                  : WhipcutTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _run(BuildContext context, bool isBn) async {
    if (videoPath == null || videoPath!.isEmpty) {
      _snack(context, _msg(PhotoMatchError.noVideo, isBn));
      return;
    }

    // Non-dismissible progress dialog for the analysis.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                isBn ? 'ছবি বিশ্লেষণ করা হচ্ছে…' : 'Analyzing photo…',
              ),
            ),
          ],
        ),
      ),
    );

    final service = PhotoMatchService();
    final result = await service.match(
      videoPath: videoPath!,
      clipDuration: clipDuration,
    );

    // Dismiss the progress dialog (the context may be gone; guard it).
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;

    if (result.cancelled) return;
    if (result.isOk) {
      // The photo's grade becomes the clip's look (LUT preserved),
      // like the "None" card replaces the look.
      onApply(ColorAdjust(
        photoCurves: result.curves,
        lutPath: currentAdjust.lutPath,
      ));
      _snack(
          context,
          isBn
              ? 'ছবির কালার ম্যাচ হয়েছে ✓ (আসল রেন্ডার এক্সপোর্টে)'
              : 'Photo colors matched ✓ (true render at export)');
    } else if (result.error != null) {
      _snack(context, _msg(result.error!, isBn));
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _msg(PhotoMatchError error, bool isBn) {
    switch (error) {
      case PhotoMatchError.noVideo:
        return isBn
            ? 'প্রথমে একটি ভিডিও ক্লিপ যোগ করুন'
            : 'Add a video clip first';
      case PhotoMatchError.unreadableImage:
        return isBn ? 'ছবিটি পড়া যায়নি' : "Couldn't read the image";
      case PhotoMatchError.imageTooSmall:
        return isBn
            ? 'ছবিটি খুব ছোট — বড় ছবি বেছে নিন'
            : 'Image is too small — pick a larger one';
      case PhotoMatchError.frameFailed:
        return isBn
            ? 'ভিডিও থেকে ফ্রেম নেওয়া যায়নি'
            : "Couldn't grab a video frame";
    }
  }
}
