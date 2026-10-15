import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:whipcut/core/theme.dart';
import 'package:whipcut/data/project_repository.dart';
import 'package:whipcut/features/adjust/adjust_screen.dart';
import 'package:whipcut/features/audio/audio_screen.dart';
import 'package:whipcut/features/export/export_screen.dart';
import 'package:whipcut/features/text_overlay/text_overlay_screen.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';
import 'package:whipcut/models/project.dart';
import 'package:whipcut/models/timeline.dart';

import 'editor_providers.dart';
import 'widgets/timeline_view.dart';

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Cross-agent contracts (verified against the real sibling files).
// Agent B — models/project.dart / data/project_repository.dart:
//   - `WhipcutProject`: `id`, `name`, `aspectRatio` (AspectRatioPreset with
//     `.ratio` via the AspectRatioPresetX extension), `createdAt`,
//     `updatedAt`, `timeline` (TimelineProject),
//     `copyWith({..., TimelineProject? timeline})`.
//   - `projectRepositoryProvider`: `Future<void> saveProject(WhipcutProject)`.
//   - `currentProjectProvider`: `StateProvider<WhipcutProject?>`.
// Agents D1/D2/E — verified constructors, all
//   `({super.key, required this.project})` with `final WhipcutProject project`:
//   - `AdjustScreen` (features/adjust/adjust_screen.dart)
//   - `TextOverlayScreen` (features/text_overlay/text_overlay_screen.dart)
//   - `AudioScreen` (features/audio/audio_screen.dart)
//   - `ExportScreen` (features/export/export_screen.dart)
// ---------------------------------------------------------------------------
// INTEGRATION (2026-10-15): before pushing any panel screen above, the
// editor commits its working timeline into `currentProjectProvider` (via
// `_syncWorkingCopy`) and passes the synced project to the panel; on pop,
// `_refreshWorkingCopyFromProvider` adopts the panel's edits back.
// ---------------------------------------------------------------------------

/// Video editor screen — preview + multi-track timeline + toolbars.
///
/// Constructed by the projects agent as `EditorScreen(project: project)`.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.project});

  final WhipcutProject project;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  VideoPlayerController? _previewController;
  String? _previewPath;
  int _previewToken = 0;
  bool _wasPlaying = false;

  Timer? _transportTimer;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _transportTimer =
        Timer.periodic(const Duration(milliseconds: 100), (_) => _tickTransport());
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPreview());
  }

  @override
  void dispose() {
    _transportTimer?.cancel();
    _saveTimer?.cancel();
    _previewController?.dispose();
    super.dispose();
  }

  // Preview ---------------------------------------------------------------

  /// Loads the first playable video clip into the preview player.
  Future<void> _syncPreview() async {
    final token = ++_previewToken;
    final clip = ref
        .read(timelineEditorProvider(widget.project).notifier)
        .firstPlayableVideoClip;
    final path = clip?.mediaPath;
    if (path == _previewPath) return;
    _previewPath = path;

    final old = _previewController;
    _previewController = null;
    await old?.dispose();
    if (!mounted || token != _previewToken) return;
    setState(() {});

    if (path == null) return;
    final controller = VideoPlayerController.file(File(path));
    _previewController = controller;
    try {
      await controller.initialize();
    } catch (_) {
      return; // unreadable file — placeholder stays
    }
    if (!mounted || token != _previewToken) {
      await controller.dispose();
      return;
    }
    setState(() {});
  }

  /// 10Hz transport tick: follows the preview player's position.
  void _tickTransport() {
    final controller = _previewController;
    if (!mounted || controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying != _wasPlaying) {
      _wasPlaying = controller.value.isPlaying;
      setState(() {});
    }
    if (!controller.value.isPlaying) return;
    final notifier =
        ref.read(timelineEditorProvider(widget.project).notifier);
    final clip = notifier.firstPlayableVideoClip;
    if (clip == null) return;
    final pos = controller.value.position.inMilliseconds / 1000.0;
    notifier.setPlayhead(clip.start + pos);
  }

  Future<void> _togglePlay() async {
    final controller = _previewController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      final notifier =
          ref.read(timelineEditorProvider(widget.project).notifier);
      final clip = notifier.firstPlayableVideoClip;
      final playhead = notifier.playhead;
      if (clip != null && playhead >= clip.start && playhead <= clip.end) {
        await controller.seekTo(
          Duration(milliseconds: ((playhead - clip.start) * 1000).round()),
        );
      }
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  // Import ------------------------------------------------------------------

  Future<void> _importVideo() async {
    final picked =
        await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final duration = await probeVideoDuration(picked.path);
    if (!mounted) return;
    ref.read(timelineEditorProvider(widget.project).notifier).addClip(
          TrackType.video,
          buildImportedVideoClip(
            mediaPath: picked.path,
            sourceDuration: duration,
          ),
        );
  }

  // Autosave ------------------------------------------------------------------

  void _scheduleAutosave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _autosaveNow);
  }

  Future<void> _autosaveNow() async {
    try {
      final timeline =
          ref.read(timelineEditorProvider(widget.project)).project;
      // Base the write on the provider (which panel screens update), not the
      // stale constructor arg, so editor autosaves never clobber panel edits.
      final current = ref.read(currentProjectProvider);
      final base = (current != null && current.id == widget.project.id)
          ? current
          : widget.project;
      final updated = base.copyWith(
        timeline: timeline,
        updatedAt: DateTime.now(),
      );
      await ref.read(projectRepositoryProvider).saveProject(updated);
      ref.read(currentProjectProvider.notifier).state = updated;
    } catch (_) {
      // Autosave is best-effort; surfaced on next successful save.
    }
  }

  // Clip ops ------------------------------------------------------------------

  TimelineEditorNotifier get _notifier =>
      ref.read(timelineEditorProvider(widget.project).notifier);

  String? get _selectedClipId =>
      ref.read(timelineEditorProvider(widget.project)).selectedClipId;

  void _requireClip(VoidCallback run) {
    if (_selectedClipId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).selectClip)),
      );
      return;
    }
    run();
  }

  void _onTrim() {
    _requireClip(() {
      final found = _notifier.findClip(_selectedClipId!);
      if (found == null || !mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => _TrimDialog(
          project: widget.project,
          clipId: found.clip.id,
        ),
      );
    });
  }

  void _onSplit() {
    _requireClip(() {
      final ok = _notifier.splitClipAt(
        _selectedClipId!,
        _notifier.playhead,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).selectClip)),
        );
      }
    });
  }

  void _onDelete() {
    _requireClip(() => _notifier.rippleDelete(_selectedClipId!));
  }

  void _onSpeed() {
    _requireClip(() {
      const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0];
      showDialog<double>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(AppLocalizations.of(ctx).speed),
          children: [
            for (final s in speeds)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(s),
                child: Text('${s}x'),
              ),
          ],
        ),
      ).then((speed) {
        if (speed != null) _notifier.setSpeed(_selectedClipId!, speed);
      });
    });
  }

  void _onReverse() {
    _requireClip(() => _notifier.toggleReverse(_selectedClipId!));
  }

  /// Commits the editor's working timeline into [currentProjectProvider]
  /// and disk, and returns the synced project. Called before opening a panel
  /// screen (Adjust/Text/Audio/Export), which all edit [currentProjectProvider]
  /// — so they see the latest timeline rather than the (possibly stale)
  /// project this screen was constructed with. (Integration, 2026-10-15.)
  Future<WhipcutProject> _syncWorkingCopy() async {
    final working =
        ref.read(timelineEditorProvider(widget.project)).project;
    final current = ref.read(currentProjectProvider);
    final base = (current != null && current.id == widget.project.id)
        ? current
        : widget.project;
    final synced = base.copyWith(
      timeline: working,
      updatedAt: DateTime.now(),
    );
    ref.read(currentProjectProvider.notifier).state = synced;
    try {
      await ref.read(projectRepositoryProvider).saveProject(synced);
    } catch (_) {
      // Disk write is best-effort; the in-memory provider is authoritative.
    }
    return synced;
  }

  /// After a panel screen pops, its edits live in [currentProjectProvider].
  /// Adopts them into the editor's working copy (keeping the undo history)
  /// so the next editor edit/autosave doesn't clobber them.
  /// (Integration, 2026-10-15.)
  void _refreshWorkingCopyFromProvider() {
    final current = ref.read(currentProjectProvider);
    if (current == null || current.id != widget.project.id) return;
    ref
        .read(timelineEditorProvider(widget.project).notifier)
        .adoptExternalTimeline(current.timeline);
  }

  Future<void> _openPanel(
      Widget Function(WhipcutProject project) buildScreen) async {
    final synced = await _syncWorkingCopy();
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => buildScreen(synced)));
    _refreshWorkingCopyFromProvider();
  }

  // Build ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<TimelineEditorState>(
      timelineEditorProvider(widget.project),
      (_, _) {
        _scheduleAutosave();
        _syncPreview();
      },
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.editor)),
      body: Column(
        children: [
          Expanded(child: _buildPreview(l10n)),
          _TransportRow(
            project: widget.project,
            playing: _previewController?.value.isInitialized == true &&
                _previewController!.value.isPlaying,
            onTogglePlay: _togglePlay,
            onImport: _importVideo,
          ),
          SizedBox(
            height: 248,
            child: TimelineView(project: widget.project),
          ),
          _Toolbar(
            project: widget.project,
            onTrim: _onTrim,
            onSplit: _onSplit,
            onDelete: _onDelete,
            onSpeed: _onSpeed,
            onReverse: _onReverse,
            onColor: () => _openPanel((p) => AdjustScreen(project: p)),
            onText: () =>
                _openPanel((p) => TextOverlayScreen(project: p)),
            onAudio: () => _openPanel((p) => AudioScreen(project: p)),
            onExport: () => _openPanel((p) => ExportScreen(project: p)),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(AppLocalizations l10n) {
    final controller = _previewController;

    Widget content;
    if (controller != null && controller.value.isInitialized) {
      content = VideoPlayer(controller);
    } else if (_previewPath != null) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.video_library_outlined,
              size: 56,
              color: WhipcutTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _importVideo,
              icon: const Icon(Icons.add),
              label: Text(l10n.importVideo),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: widget.project.aspectRatio.ratio,
          child: content,
        ),
      ),
    );
  }
}

/// Transport controls: play/pause, time, snap, zoom, import.
class _TransportRow extends ConsumerWidget {
  const _TransportRow({
    required this.project,
    required this.playing,
    required this.onTogglePlay,
    required this.onImport,
  });

  final WhipcutProject project;
  final bool playing;
  final VoidCallback onTogglePlay;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final editorState = ref.watch(timelineEditorProvider(project));
    final notifier = ref.read(timelineEditorProvider(project).notifier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: WhipcutTheme.surface,
        border: Border(
          top: BorderSide(color: WhipcutTheme.surfaceOutline),
          bottom: BorderSide(color: WhipcutTheme.surfaceOutline),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: playing ? l10n.pause : l10n.play,
            onPressed: onTogglePlay,
            icon: Icon(
              playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
              size: 32,
              color: WhipcutTheme.amber,
            ),
          ),
          _TimeDisplay(project: project),
          IconButton(
            tooltip: l10n.importVideo,
            onPressed: onImport,
            icon: const Icon(Icons.video_library_outlined, size: 22),
          ),
          const Spacer(),
          IconButton(
            tooltip: l10n.snap,
            onPressed: notifier.toggleSnap,
            icon: Icon(
              Icons.straighten,
              size: 22,
              color: editorState.snapEnabled
                  ? WhipcutTheme.amber
                  : WhipcutTheme.textSecondary,
            ),
          ),
          const Icon(Icons.zoom_in, size: 18, color: WhipcutTheme.textSecondary),
          SizedBox(
            width: 110,
            child: Slider(
              value: editorState.pxPerSecond,
              min: 16,
              max: 240,
              label: l10n.zoom,
              onChanged: notifier.setZoom,
            ),
          ),
        ],
      ),
    );
  }
}

/// Playhead time / project duration. Watches only the playhead value.
class _TimeDisplay extends ConsumerWidget {
  const _TimeDisplay({required this.project});

  final WhipcutProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playhead = ref.watch(
      timelineEditorProvider(project).select((s) => s.playhead),
    );
    final duration = ref.watch(
      timelineEditorProvider(project).select((s) => s.project.duration),
    );
    return Text(
      '${_fmt(playhead)} / ${_fmt(duration)}',
      style: const TextStyle(
        color: WhipcutTheme.textSecondary,
        fontSize: 12,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  String _fmt(double seconds) {
    final total = seconds.floor();
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    final tenths = ((seconds - total) * 10).floor();
    return '$m:$s.$tenths';
  }
}

/// Bottom toolbar: clip ops + panel shortcuts.
class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.project,
    required this.onTrim,
    required this.onSplit,
    required this.onDelete,
    required this.onSpeed,
    required this.onReverse,
    required this.onColor,
    required this.onText,
    required this.onAudio,
    required this.onExport,
  });

  final WhipcutProject project;
  final VoidCallback onTrim;
  final VoidCallback onSplit;
  final VoidCallback onDelete;
  final VoidCallback onSpeed;
  final VoidCallback onReverse;
  final VoidCallback onColor;
  final VoidCallback onText;
  final VoidCallback onAudio;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(timelineEditorProvider(project).notifier);
    // Rebuild when undo/redo availability changes (any project change).
    ref.watch(timelineEditorProvider(project).select((s) => s.project));

    return Container(
      decoration: const BoxDecoration(
        color: WhipcutTheme.surface,
        border: Border(top: BorderSide(color: WhipcutTheme.surfaceOutline)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              _ToolButton(
                  icon: Icons.content_cut, label: l10n.trim, onPressed: onTrim),
              _ToolButton(
                  icon: Icons.call_split,
                  label: l10n.split,
                  onPressed: onSplit),
              _ToolButton(
                  icon: Icons.delete_outline,
                  label: l10n.delete,
                  onPressed: onDelete),
              _ToolButton(
                  icon: Icons.speed, label: l10n.speed, onPressed: onSpeed),
              _ToolButton(
                  icon: Icons.swap_horiz,
                  label: l10n.reverse,
                  onPressed: onReverse),
              _ToolButton(
                  icon: Icons.undo,
                  label: l10n.undo,
                  onPressed: notifier.canUndo ? notifier.undo : null),
              _ToolButton(
                  icon: Icons.redo,
                  label: l10n.redo,
                  onPressed: notifier.canRedo ? notifier.redo : null),
              const _ToolbarDivider(),
              _ToolButton(
                  icon: Icons.tune, label: l10n.color, onPressed: onColor),
              _ToolButton(
                  icon: Icons.title, label: l10n.text, onPressed: onText),
              _ToolButton(
                  icon: Icons.graphic_eq, label: l10n.audio, onPressed: onAudio),
              _ToolButton(
                  icon: Icons.ios_share,
                  label: l10n.export,
                  onPressed: onExport,
                  highlight: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null
        ? WhipcutTheme.textSecondary.withValues(alpha: 0.4)
        : highlight
            ? WhipcutTheme.amber
            : WhipcutTheme.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 10, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        height: 36,
        child: VerticalDivider(color: WhipcutTheme.surfaceOutline, width: 1),
      ),
    );
  }
}

/// Trim dialog: source-range sliders over the clip's full source duration.
class _TrimDialog extends StatefulWidget {
  const _TrimDialog({required this.project, required this.clipId});

  final WhipcutProject project;
  final String clipId;

  @override
  State<_TrimDialog> createState() => _TrimDialogState();
}

class _TrimDialogState extends State<_TrimDialog> {
  double? _sourceDuration;
  late double _trimStart;
  late double _trimEnd;

  @override
  void initState() {
    super.initState();
    final container = ProviderScope.containerOf(context, listen: false);
    final found = container
        .read(timelineEditorProvider(widget.project).notifier)
        .findClip(widget.clipId);
    final clip = found!.clip;
    _trimStart = clip.sourceStart;
    _trimEnd = clip.sourceStart + clip.duration;
    probeVideoDuration(clip.mediaPath).then((d) {
      if (!mounted) return;
      setState(() {
        // Source duration must at least cover the current trim window.
        _sourceDuration = d < _trimEnd ? _trimEnd : d;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final max = _sourceDuration;

    return AlertDialog(
      title: Text(l10n.trim),
      content: SizedBox(
        width: 320,
        child: max == null
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.trimStart,
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(_fmt(_trimStart),
                          style:
                              const TextStyle(color: WhipcutTheme.amber)),
                    ],
                  ),
                  Slider(
                    value: _trimStart.clamp(0.0, max),
                    min: 0,
                    max: max,
                    divisions: (max * 10).round().clamp(1, 1000),
                    onChanged: (v) => setState(() {
                      _trimStart = v.clamp(0.0, _trimEnd - 0.1);
                    }),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.trimEnd,
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(_fmt(_trimEnd),
                          style:
                              const TextStyle(color: WhipcutTheme.amber)),
                    ],
                  ),
                  Slider(
                    value: _trimEnd.clamp(0.0, max),
                    min: 0,
                    max: max,
                    divisions: (max * 10).round().clamp(1, 1000),
                    onChanged: (v) => setState(() {
                      _trimEnd = v.clamp(_trimStart + 0.1, max);
                    }),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: max == null
              ? null
              : () {
                  ProviderScope.containerOf(context, listen: false)
                      .read(timelineEditorProvider(widget.project).notifier)
                      .trimClip(widget.clipId, _trimStart, _trimEnd);
                  Navigator.of(context).pop();
                },
          child: Text(l10n.done),
        ),
      ],
    );
  }

  String _fmt(double seconds) {
    final total = seconds.floor();
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
