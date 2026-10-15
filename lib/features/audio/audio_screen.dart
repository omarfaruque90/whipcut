import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:whipcut/core/theme.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';

// Integration: models/project.dart + data/project_repository.dart (Agent B,
// landed) and models/timeline.dart (Agent C, landed): TrackType,
// TimelineTrack (id, type, clips, copyWith), TimelineClip (id, mediaPath,
// start, duration, sourceStart, speed, reversed, volume, fadeIn, fadeOut,
// colorAdjust, copyWith), TimelineProject (tracks, textOverlays, duration,
// copyWith).
// ---------------------------------------------------------------------------
import 'package:whipcut/models/timeline.dart';
import 'package:whipcut/models/project.dart';
import 'package:whipcut/data/project_repository.dart';

/// Which audio clip is being edited in this screen instance.
final _selectedClipIdProvider = StateProvider.autoDispose<String?>((_) => null);

/// Audio screen: music import, voice-over recording, per-clip volume/fades.
///
/// NOTE (export): imported/recorded clips get a *placeholder* duration equal
/// to the timeline duration. The export agent must re-probe the actual audio
/// duration with ffprobe at render time and clamp/extend accordingly.
class AudioScreen extends ConsumerWidget {
  const AudioScreen({super.key, required this.project});

  final WhipcutProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final clips = _audioClips(project);
    final selectedId = ref.watch(_selectedClipIdProvider);
    final selected = clips.where((c) => c.id == selectedId).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.audio)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _importMusic(context, ref),
                  icon: const Icon(Icons.library_music_outlined),
                  label: Text(l10n.importMusic),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _VoiceoverButton(
                  onRecorded: (path) =>
                      _addAudioClip(ref, mediaPath: path, context: context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (clips.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.audiotrack, size: 56, color: WhipcutTheme.textSecondary),
                    const SizedBox(height: 12),
                    Text(l10n.noAudioTracks, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            )
          else
            ...clips.map(
              (clip) => _AudioClipCard(
                clip: clip,
                selected: clip.id == selectedId,
                onTap: () => ref.read(_selectedClipIdProvider.notifier).state =
                    clip.id == selectedId ? null : clip.id,
                onDelete: () => _deleteClip(context, ref, clip),
              ),
            ),
          if (selected != null) ...[
            const SizedBox(height: 8),
            _ClipEditor(
              key: ValueKey(selected.id),
              project: project,
              clip: selected,
            ),
          ],
        ],
      ),
    );
  }

  static List<TimelineClip> _audioClips(WhipcutProject project) => project
      .timeline.tracks
      .where((t) => t.type == TrackType.audio)
      .expand((t) => t.clips)
      .toList();

  Future<void> _persist(WidgetRef ref, WhipcutProject updated) async {
    await ref.read(projectRepositoryProvider).saveProject(updated);
    ref.read(currentProjectProvider.notifier).state = updated;
  }

  Future<void> _deleteClip(BuildContext context, WidgetRef ref, TimelineClip clip) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(
          clip.mediaPath.split(Platform.pathSeparator).last,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete, style: const TextStyle(color: WhipcutTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final tracks = project.timeline.tracks
        .map((t) => t.type == TrackType.audio
            ? t.copyWith(clips: t.clips.where((c) => c.id != clip.id).toList())
            : t)
        .toList();
    if (ref.read(_selectedClipIdProvider) == clip.id) {
      ref.read(_selectedClipIdProvider.notifier).state = null;
    }
    await _persist(
      ref,
      project.copyWith(
        timeline: project.timeline.copyWith(tracks: tracks),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _importMusic(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    final srcPath = result?.files.singleOrNull?.path;
    if (srcPath == null) return;

    final mediaDir = await _projectMediaDir(project.id);
    final name = result!.files.single.name;
    final dest = File('${mediaDir.path}${Platform.pathSeparator}$name');
    await File(srcPath).copy(dest.path);
    if (!context.mounted) return;

    await _addAudioClip(
      ref,
      mediaPath: dest.path,
      context: context,
    );
  }

  /// Appends an audio clip at the end of the timeline on the first audio
  /// track (creating the track if the project has none).
  Future<void> _addAudioClip(
    WidgetRef ref, {
    required String mediaPath,
    required BuildContext context,
  }) async {
    final placeholder = project.timeline.duration;
    final clip = TimelineClip(
      id: const Uuid().v4(),
      mediaPath: mediaPath,
      start: project.timeline.duration,
      duration: placeholder, // re-probed at export; see class doc.
      sourceStart: 0,
      speed: 1,
      reversed: false,
      volume: 1,
      fadeIn: 0,
      fadeOut: 0,
    );

    var tracks = List.of(project.timeline.tracks);
    final audioIdx = tracks.indexWhere((t) => t.type == TrackType.audio);
    if (audioIdx >= 0) {
      tracks[audioIdx] =
          tracks[audioIdx].copyWith(clips: [...tracks[audioIdx].clips, clip]);
    } else {
      tracks.add(_newAudioTrack(clip));
    }

    await _persist(
      ref,
      project.copyWith(
        timeline: project.timeline.copyWith(tracks: tracks),
        updatedAt: DateTime.now(),
      ),
    );
    if (context.mounted) {
      ref.read(_selectedClipIdProvider.notifier).state = clip.id;
    }
  }

  /// Project media dir: `<app docs>/whipcut_projects/<projectId>/media`.
  /// Agent B: if you store project media elsewhere, align this helper.
  static Future<Directory> _projectMediaDir(String projectId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}whipcut_projects'
      '${Platform.pathSeparator}$projectId'
      '${Platform.pathSeparator}media',
    );
    return dir.create(recursive: true).then((_) => dir);
  }

  // Agent C: adjust to TimelineTrack's real constructor.
  static TimelineTrack _newAudioTrack(TimelineClip firstClip) =>
      TimelineTrack(id: const Uuid().v4(), type: TrackType.audio, clips: [firstClip]);
}

/// Voice-over record/stop button.
///
/// Saves to `<app docs>/voiceovers/vo_<timestamp>.m4a` (AAC-LC), then reports
/// the file path via [onRecorded] so the parent can add it as an audio clip.
class _VoiceoverButton extends ConsumerStatefulWidget {
  const _VoiceoverButton({required this.onRecorded});

  final ValueChanged<String> onRecorded;

  @override
  ConsumerState<_VoiceoverButton> createState() => _VoiceoverButtonState();
}

class _VoiceoverButtonState extends ConsumerState<_VoiceoverButton> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  int _seconds = 0;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: _recording ? WhipcutTheme.danger : WhipcutTheme.amber,
        side: BorderSide(
          color: _recording ? WhipcutTheme.danger : WhipcutTheme.amber,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: _recording ? _stop : _start,
      icon: Icon(_recording ? Icons.stop : Icons.mic_outlined),
      label: Text(
        _recording ? '${l10n.stopRecording} ${_fmt(_seconds.toDouble())}' : l10n.recordVoiceover,
      ),
    );
  }

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.recordingPermissionDenied)),
      );
      return;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = await Directory('${docs.path}${Platform.pathSeparator}voiceovers')
        .create(recursive: true);
    final path =
        '${dir.path}${Platform.pathSeparator}vo_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    if (!mounted) return;
    setState(() {
      _recording = true;
      _seconds = 0;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null) return;
    widget.onRecorded(path);
  }
}

/// Per-clip editor: volume (0..1) and fade in/out (0..5s) sliders.
/// Drags update local state at 120Hz; persistence is debounced.
class _ClipEditor extends ConsumerStatefulWidget {
  const _ClipEditor({super.key, required this.project, required this.clip});

  final WhipcutProject project;
  final TimelineClip clip;

  @override
  ConsumerState<_ClipEditor> createState() => _ClipEditorState();
}

class _ClipEditorState extends ConsumerState<_ClipEditor> {
  late TimelineClip _working;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _working = widget.clip;
  }

  @override
  void didUpdateWidget(covariant _ClipEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync external changes (e.g. after our own persist round-trip) unless
    // we have unsaved local edits in flight.
    if (_saveTimer?.isActive != true && widget.clip != _working) {
      _working = widget.clip;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  void _onChanged(TimelineClip Function(TimelineClip) update) {
    setState(() => _working = update(_working));
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _persist);
  }

  Future<void> _persist() async {
    final clipId = _working.id;
    final working = _working;
    final tracks = widget.project.timeline.tracks.map((t) {
      if (t.type != TrackType.audio || !t.clips.any((c) => c.id == clipId)) return t;
      return t.copyWith(
        clips: t.clips.map((c) => c.id == clipId ? working : c).toList(),
      );
    }).toList();
    final updated = widget.project.copyWith(
      timeline: widget.project.timeline.copyWith(tracks: tracks),
      updatedAt: DateTime.now(),
    );
    await ref.read(projectRepositoryProvider).saveProject(updated);
    ref.read(currentProjectProvider.notifier).state = updated;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _working.mediaPath.split(Platform.pathSeparator).last,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            _SliderRow(
              label: '${l10n.volume}: ${(_working.volume * 100).round()}%',
              value: _working.volume,
              min: 0,
              max: 1,
              onChanged: (v) => _onChanged((c) => c.copyWith(volume: v)),
            ),
            _SliderRow(
              label: '${l10n.fadeIn}: ${_fmt(_working.fadeIn)}',
              value: _working.fadeIn,
              min: 0,
              max: 5,
              onChanged: (v) => _onChanged((c) => c.copyWith(fadeIn: v)),
            ),
            _SliderRow(
              label: '${l10n.fadeOut}: ${_fmt(_working.fadeOut)}',
              value: _working.fadeOut,
              min: 0,
              max: 5,
              onChanged: (v) => _onChanged((c) => c.copyWith(fadeOut: v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          Slider(value: value, min: min, max: max, onChanged: onChanged),
        ],
      );
}

/// One audio clip row: filename, timing, delete. Tap to select for editing.
class _AudioClipCard extends StatelessWidget {
  const _AudioClipCard({
    required this.clip,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final TimelineClip clip;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? WhipcutTheme.amber : WhipcutTheme.surfaceOutline,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.audiotrack),
        title: Text(
          clip.mediaPath.split(Platform.pathSeparator).last,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_fmt(clip.start)} – ${_fmt(clip.start + clip.duration)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: IconButton(
          tooltip: l10n.delete,
          icon: const Icon(Icons.delete_outline, color: WhipcutTheme.danger),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

String _fmt(double seconds) {
  final s = seconds.round();
  final m = s ~/ 60;
  return '$m:${(s % 60).toString().padLeft(2, '0')}';
}
