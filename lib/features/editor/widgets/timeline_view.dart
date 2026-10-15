import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whipcut/core/theme.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';
import 'package:whipcut/models/project.dart';
import 'package:whipcut/models/timeline.dart';

import '../editor_providers.dart';

const double _gutterWidth = 44;
const double _rulerHeight = 28;
const double _videoRowHeight = 64;
const double _audioRowHeight = 48;
const double _textRowHeight = 40;

/// Multi-track timeline: ruler + one row per track + amber playhead.
///
/// Scrub by dragging on the ruler. Tap a clip to select it, tap empty space
/// to deselect. The playhead line is an isolated consumer so 10Hz transport
/// ticks don't rebuild the whole timeline.
class TimelineView extends ConsumerWidget {
  const TimelineView({super.key, required this.project});

  final WhipcutProject project;

  double _rowHeight(TrackType type) => switch (type) {
        TrackType.video => _videoRowHeight,
        TrackType.audio => _audioRowHeight,
        TrackType.text => _textRowHeight,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState =
        ref.watch(timelineEditorProvider(project));
    final timeline = editorState.project;
    final px = editorState.pxPerSecond;
    final totalWidth = (timeline.duration * px + 64).clamp(320.0, 20000.0);

    final tracks = timeline.tracks;
    final hasTextOverlays = timeline.textOverlays.isNotEmpty;
    // Render a text lane when there are overlays even without a text track.
    final showTextLane =
        tracks.any((t) => t.type == TrackType.text) || hasTextOverlays;

    return Container(
      color: WhipcutTheme.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gutter: ruler corner + track headers.
          SizedBox(
            width: _gutterWidth,
            child: Column(
              children: [
                const SizedBox(height: _rulerHeight),
                for (final track in tracks)
                  SizedBox(
                    height: _rowHeight(track.type),
                    child: Center(child: _TrackHeaderIcon(type: track.type)),
                  ),
                if (showTextLane &&
                    !tracks.any((t) => t.type == TrackType.text))
                  const SizedBox(
                    height: _textRowHeight,
                    child: Center(
                        child: _TrackHeaderIcon(type: TrackType.text)),
                  ),
              ],
            ),
          ),
          // Scrollable lanes.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ref
                    .read(timelineEditorProvider(project).notifier)
                    .selectClip(null),
                child: SizedBox(
                  width: totalWidth,
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _RulerStrip(
                            project: project,
                            width: totalWidth,
                          ),
                          for (final track in tracks)
                            _TrackLane(
                              project: project,
                              track: track,
                              width: totalWidth,
                              height: _rowHeight(track.type),
                            ),
                          if (showTextLane &&
                              !tracks.any((t) => t.type == TrackType.text))
                            _TextOverlayLane(
                              project: project,
                              width: totalWidth,
                              height: _textRowHeight,
                            ),
                          if (tracks.isEmpty && !hasTextOverlays)
                            SizedBox(
                              width: totalWidth,
                              height: 120,
                              child: Center(
                                child: Text(
                                  AppLocalizations.of(context).importVideo,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                        ],
                      ),
                      _PlayheadLine(project: project, width: totalWidth),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackHeaderIcon extends StatelessWidget {
  const _TrackHeaderIcon({required this.type});

  final TrackType type;

  @override
  Widget build(BuildContext context) {
    final icon = switch (type) {
      TrackType.video => Icons.movie_outlined,
      TrackType.audio => Icons.graphic_eq,
      TrackType.text => Icons.title,
    };
    return Icon(icon, size: 20, color: WhipcutTheme.textSecondary);
  }
}

/// Ruler with time ticks; dragging here scrubs the playhead.
class _RulerStrip extends ConsumerWidget {
  const _RulerStrip({required this.project, required this.width});

  final WhipcutProject project;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState =
        ref.watch(timelineEditorProvider(project));
    final notifier =
        ref.read(timelineEditorProvider(project).notifier);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _scrub(d.localPosition.dx, notifier),
      onPanStart: (d) => _scrub(d.localPosition.dx, notifier),
      onPanUpdate: (d) => _scrub(d.localPosition.dx, notifier),
      child: SizedBox(
        width: width,
        height: _rulerHeight,
        child: CustomPaint(
          painter: _RulerPainter(
            pxPerSecond: editorState.pxPerSecond,
            duration: editorState.project.duration,
          ),
        ),
      ),
    );
  }

  void _scrub(double dx, TimelineEditorNotifier notifier) {
    final raw =
        (dx / notifier.pxPerSecond).clamp(0.0, notifier.projectDuration);
    notifier.setPlayhead(notifier.snapTime(raw.toDouble(), 10));
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.pxPerSecond, required this.duration});

  final double pxPerSecond;
  final double duration;

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = WhipcutTheme.surfaceOutline
      ..strokeWidth = 1;
    final labelStyle = const TextStyle(
      color: WhipcutTheme.textSecondary,
      fontSize: 10,
    );
    final labelEvery = pxPerSecond < 36 ? 10 : 5;
    final totalSeconds = duration.ceil();
    for (var s = 0; s <= totalSeconds; s++) {
      final x = s * pxPerSecond;
      final isLabel = s % labelEvery == 0;
      canvas.drawLine(
        Offset(x, size.height - (isLabel ? 14 : 7)),
        Offset(x, size.height),
        tickPaint,
      );
      if (isLabel) {
        final tp = TextPainter(
          text: TextSpan(text: _formatTime(s.toDouble()), style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 4, 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.pxPerSecond != pxPerSecond || old.duration != duration;
}

String _formatTime(double seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toStringAsFixed(0).padLeft(2, '0');
  return '$m:$s';
}

/// One track lane with its clip blocks.
class _TrackLane extends ConsumerWidget {
  const _TrackLane({
    required this.project,
    required this.track,
    required this.width,
    required this.height,
  });

  final WhipcutProject project;
  final TimelineTrack track;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState =
        ref.watch(timelineEditorProvider(project));
    final px = editorState.pxPerSecond;

    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: WhipcutTheme.surfaceOutline, width: 0.5),
        ),
      ),
      child: Stack(
        children: [
          for (final clip in track.clips)
            Positioned(
              left: clip.start * px,
              top: 6,
              width: (clip.duration * px).clamp(8.0, width),
              height: height - 12,
              child: _ClipBlock(project: project, clip: clip),
            ),
        ],
      ),
    );
  }
}

/// Lane that renders text overlays when no text track exists.
class _TextOverlayLane extends ConsumerWidget {
  const _TextOverlayLane({
    required this.project,
    required this.width,
    required this.height,
  });

  final WhipcutProject project;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlays =
        ref.watch(timelineEditorProvider(project)).project.textOverlays;
    final px =
        ref.watch(timelineEditorProvider(project)).pxPerSecond;
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: WhipcutTheme.surfaceOutline, width: 0.5),
        ),
      ),
      child: Stack(
        children: [
          for (final overlay in overlays)
            Positioned(
              left: overlay.start * px,
              top: 6,
              width: (overlay.duration * px).clamp(8.0, width),
              height: height - 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: WhipcutTheme.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: WhipcutTheme.amber.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  overlay.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WhipcutTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Selectable clip block. Tapping selects; selected gets the amber border.
class _ClipBlock extends ConsumerWidget {
  const _ClipBlock({required this.project, required this.clip});

  final WhipcutProject project;
  final TimelineClip clip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected =
        ref.watch(timelineEditorProvider(project)).selectedClipId == clip.id;

    return GestureDetector(
      onTap: () => ref
          .read(timelineEditorProvider(project).notifier)
          .selectClip(clip.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: WhipcutTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? WhipcutTheme.amber : WhipcutTheme.surfaceOutline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.movie, size: 12, color: WhipcutTheme.amber),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _formatTime(clip.duration),
                    maxLines: 1,
                    style: const TextStyle(
                      color: WhipcutTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (clip.speed != 1.0)
                  Text(
                    '${clip.speed}x',
                    style: const TextStyle(
                      color: WhipcutTheme.amber,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (clip.reversed)
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(
                      Icons.swap_horiz,
                      size: 12,
                      color: WhipcutTheme.amber,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Amber playhead line. Watches only the playhead value.
class _PlayheadLine extends ConsumerWidget {
  const _PlayheadLine({required this.project, required this.width});

  final WhipcutProject project;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playhead = ref.watch(
      timelineEditorProvider(project).select((s) => s.playhead),
    );
    final px = ref.watch(
      timelineEditorProvider(project).select((s) => s.pxPerSecond),
    );
    final x = (playhead * px).clamp(0.0, width);

    return Positioned(
      left: x - 1,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: SizedBox(
          width: 2,
          child: Column(
            children: [
              Container(
                width: 10,
                height: 12,
                decoration: const BoxDecoration(
                  color: WhipcutTheme.amber,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
              ),
              const Expanded(
                child: ColoredBox(
                  color: WhipcutTheme.amber,
                  child: SizedBox(width: 2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
