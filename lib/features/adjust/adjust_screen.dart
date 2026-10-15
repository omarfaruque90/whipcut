import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whipcut/core/theme.dart';
import 'package:whipcut/data/project_repository.dart';
import 'package:whipcut/features/filters/filter_gallery.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';
import 'package:whipcut/models/color_adjust.dart';
import 'package:whipcut/models/project.dart';
import 'package:whipcut/models/timeline.dart';

/// Color/Adjust panel (Agent D1).
///
/// ## Contracts coded against (Agent B / Agent C)
///
/// - `WhipcutProject` (models/project.dart): fields `id`, `name`,
///   `aspectRatio`, `createdAt`, `updatedAt`, `timeline`, plus
///   `copyWith({..., TimelineProject? timeline})`.
/// - `TimelineProject` (models/timeline.dart, Agent C): `tracks`
///   (`List<TimelineTrack>`) and `copyWith({List<TimelineTrack>? tracks})`.
/// - `TimelineTrack`: `type` ([TrackType]), `clips` (`List<TimelineClip>`),
///   `copyWith({List<TimelineClip>? clips})`.
/// - `TimelineClip`: `id` (String), `duration` (double, seconds),
///   `colorAdjust` ([ColorAdjust]), `copyWith({ColorAdjust? colorAdjust})`.
/// - `TrackType` enum with a `video` value.
/// - `projectRepositoryProvider` (data/project_repository.dart):
///   `Future<void> saveProject(WhipcutProject project)`.
/// - `currentProjectProvider`: `StateProvider<WhipcutProject?>`.
///
/// Agent C pushes this screen with the project being edited. The constructor
/// arg seeds the UI; once edits land, [currentProjectProvider] is the live
/// source of truth.
///
/// ## Honesty note
///
/// Sliders and one-tap filters update the [ColorAdjust] model only. The
/// editor preview shows an approximation (ColorFiltered); the true pixel
/// filtering is baked at export (ffmpeg `eq` / `colortemperature` /
/// `curves` / `colorbalance` / `lut3d`, owned by the export agent). The
/// screen says so explicitly.
class AdjustScreen extends ConsumerWidget {
  const AdjustScreen({super.key, required this.project});

  final WhipcutProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Live project: the constructor arg seeds the screen; provider updates
    // from this screen (or elsewhere) take over once present.
    final live = ref.watch(currentProjectProvider) ?? project;
    final clips = _videoClips(live.timeline);

    var selected = ref.watch(_selectedClipIndexProvider);
    if (clips.isEmpty) {
      selected = -1;
    } else if (selected < 0 || selected >= clips.length) {
      selected = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.color),
        actions: [
          if (selected >= 0)
            TextButton.icon(
              onPressed: () => _applyToSelectedClip(
                ref,
                live,
                clips[selected],
                (_) => ColorAdjust.identity,
              ),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(l10n.reset),
            ),
        ],
      ),
      body: clips.isEmpty
          ? Center(
              child: Text(
                l10n.noClips,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _ClipStrip(
                  clips: clips,
                  selected: selected,
                  onSelect: (i) =>
                      ref.read(_selectedClipIndexProvider.notifier).state = i,
                ),
                const SizedBox(height: 20),
                FilterGallery(
                  currentAdjust: clips[selected].clip.colorAdjust,
                  onApply: (adjust) => _applyToSelectedClip(
                    ref,
                    live,
                    clips[selected],
                    (_) => adjust,
                  ),
                  videoPath: clips[selected].clip.mediaPath,
                  clipDuration: clips[selected].clip.duration,
                ),
                const SizedBox(height: 20),
                _SliderPanel(
                  project: live,
                  clipRef: clips[selected],
                ),
                const SizedBox(height: 20),
                _LutPanel(
                  project: live,
                  clipRef: clips[selected],
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: WhipcutTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.previewOnExport,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

// Clip addressing -----------------------------------------------------------
/// A video clip plus where it lives, so edits can be written back through
/// `TimelineTrack.copyWith(clips:)` -> `TimelineProject.copyWith(tracks:)`.
class _ClipRef {
  const _ClipRef({
    required this.trackIndex,
    required this.clipIndex,
    required this.clip,
  });

  final int trackIndex;
  final int clipIndex;
  final TimelineClip clip;
}

/// All video clips across the timeline's video tracks, in track order.
List<_ClipRef> _videoClips(TimelineProject timeline) {
  final refs = <_ClipRef>[];
  for (var ti = 0; ti < timeline.tracks.length; ti++) {
    final track = timeline.tracks[ti];
    if (track.type != TrackType.video) continue;
    for (var ci = 0; ci < track.clips.length; ci++) {
      refs.add(_ClipRef(trackIndex: ti, clipIndex: ci, clip: track.clips[ci]));
    }
  }
  return refs;
}

/// Applies [update] to the clip addressed by [clipRef], writes the new
/// project into [currentProjectProvider] immediately (keeps sliders at
/// 120Hz), and schedules a debounced [ProjectRepository.saveProject].
void _applyToSelectedClip(
  WidgetRef ref,
  WhipcutProject project,
  _ClipRef clipRef,
  ColorAdjust Function(ColorAdjust current) update,
) {
  final tracks = List<TimelineTrack>.of(project.timeline.tracks);
  final trackIndex = clipRef.trackIndex;
  if (trackIndex < 0 || trackIndex >= tracks.length) return;
  final clips = List<TimelineClip>.of(tracks[trackIndex].clips);
  final clipIndex = clipRef.clipIndex;
  if (clipIndex < 0 || clipIndex >= clips.length) return;

  clips[clipIndex] =
      clips[clipIndex].copyWith(colorAdjust: update(clips[clipIndex].colorAdjust));
  tracks[trackIndex] = tracks[trackIndex].copyWith(clips: clips);
  final updated = project.copyWith(
    timeline: project.timeline.copyWith(tracks: tracks),
    updatedAt: DateTime.now(),
  );

  ref.read(currentProjectProvider.notifier).state = updated;
  ref.read(_autosaveProvider.notifier).schedule(updated);
}

// Local state ---------------------------------------------------------------

/// Selected clip in the strip. File-local: the selection belongs to this
/// screen, not the global editor state.
final _selectedClipIndexProvider =
    StateProvider.autoDispose<int>((ref) => 0);

/// Debounced disk persistence (~500ms). In-memory provider state updates on
/// every slider tick for 120Hz feel; only the `saveProject` write is
/// delayed so disk I/O can't stall a drag.
final _autosaveProvider = NotifierProvider<_Autosave, void>(_Autosave.new);

class _Autosave extends Notifier<void> {
  Timer? _timer;

  @override
  void build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
  }

  void schedule(WhipcutProject project) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await ref.read(projectRepositoryProvider).saveProject(project);
      } catch (_) {
        // A failed autosave must never interrupt slider drags.
      }
    });
  }
}

// Clip selector strip -------------------------------------------------------

class _ClipStrip extends StatelessWidget {
  const _ClipStrip({
    required this.clips,
    required this.selected,
    required this.onSelect,
  });

  final List<_ClipRef> clips;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: clips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final isSelected = i == selected;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              width: 104,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? WhipcutTheme.amber.withValues(alpha: 0.14)
                    : WhipcutTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? WhipcutTheme.amber
                      : WhipcutTheme.surfaceOutline,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CLIP ${i + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isSelected
                          ? WhipcutTheme.amber
                          : WhipcutTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatSeconds(clips[i].clip.duration),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _formatSeconds(double seconds) {
  final total = seconds.round();
  final minutes = total ~/ 60;
  final rest = total % 60;
  return minutes > 0
      ? '$minutes:${rest.toString().padLeft(2, '0')}'
      : '${rest}s';
}

// Sliders -------------------------------------------------------------------

class _SliderPanel extends ConsumerWidget {
  const _SliderPanel({required this.project, required this.clipRef});

  final WhipcutProject project;
  final _ClipRef clipRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final adjust = clipRef.clip.colorAdjust;

    void set(ColorAdjust Function(ColorAdjust) update) =>
        _applyToSelectedClip(ref, project, clipRef, update);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          children: [
            _SliderRow(
              label: l10n.exposure,
              value: adjust.exposure,
              display: _signed(adjust.exposure),
              min: -2,
              max: 2,
              divisions: 80,
              onChanged: (v) =>
                  set((a) => a.copyWith(exposure: _round2(v))),
            ),
            _SliderRow(
              label: l10n.contrast,
              value: adjust.contrast,
              display: adjust.contrast.toStringAsFixed(2),
              min: 0,
              max: 2,
              divisions: 40,
              onChanged: (v) =>
                  set((a) => a.copyWith(contrast: _round2(v))),
            ),
            _SliderRow(
              label: l10n.saturation,
              value: adjust.saturation,
              display: adjust.saturation.toStringAsFixed(2),
              min: 0,
              max: 2,
              divisions: 40,
              onChanged: (v) =>
                  set((a) => a.copyWith(saturation: _round2(v))),
            ),
            _SliderRow(
              label: l10n.temperature,
              value: adjust.temperature,
              display: _signed(adjust.temperature),
              min: -1,
              max: 1,
              divisions: 40,
              onChanged: (v) =>
                  set((a) => a.copyWith(temperature: _round2(v))),
            ),
          ],
        ),
      ),
    );
  }
}

double _round2(double v) => (v * 100).round() / 100;

String _signed(double v) =>
    v >= 0 ? '+${v.toStringAsFixed(2)}' : v.toStringAsFixed(2);

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.display,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final String display;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: WhipcutTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                display,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: WhipcutTheme.amber,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// LUTs ----------------------------------------------------------------------

/// A `.cube` LUT imported by the user.
class _LutEntry {
  const _LutEntry({required this.name, required this.path});

  final String name;
  final String path;
}

const _kLutPrefsKey = 'whipcut_lut_presets';

final _lutListProvider =
    FutureProvider.autoDispose<List<_LutEntry>>((ref) => _loadLuts());

Future<List<_LutEntry>> _loadLuts() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kLutPrefsKey);
  if (raw == null || raw.isEmpty) return const [];
  final decoded = jsonDecode(raw) as List;
  final entries = <_LutEntry>[];
  for (final item in decoded) {
    final map = Map<String, dynamic>.from(item as Map);
    final path = map['path'];
    if (path is! String || path.isEmpty) continue;
    if (!await File(path).exists()) continue; // skip vanished files
    final name = (map['name'] as String?)?.trim();
    entries.add(_LutEntry(
      name: (name == null || name.isEmpty)
          ? path.split(Platform.pathSeparator).last
          : name,
      path: path,
    ));
  }
  entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return entries;
}

class _LutPanel extends ConsumerWidget {
  const _LutPanel({required this.project, required this.clipRef});

  final WhipcutProject project;
  final _ClipRef clipRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final activePath = clipRef.clip.colorAdjust.lutPath;
    final lutsAsync = ref.watch(_lutListProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.lut, style: theme.textTheme.titleMedium),
                OutlinedButton.icon(
                  onPressed: () => _importLut(ref),
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: Text(l10n.importLut),
                ),
              ],
            ),
            const SizedBox(height: 12),
            lutsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object e, _) => Text(
                '$e',
                style: theme.textTheme.bodySmall,
              ),
              data: (luts) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _LutChip(
                    label: l10n.noLut,
                    selected: activePath == null,
                    onTap: () => _applyToSelectedClip(
                      ref,
                      project,
                      clipRef,
                      (a) => a.copyWith(lutPath: null),
                    ),
                  ),
                  for (final lut in luts)
                    _LutChip(
                      label: lut.name,
                      selected: activePath == lut.path,
                      onTap: () => _applyToSelectedClip(
                        ref,
                        project,
                        clipRef,
                        (a) => a.copyWith(lutPath: lut.path),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.science_outlined,
                  size: 16,
                  color: WhipcutTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.lutExportNote,
                    style: theme.textTheme.bodySmall,
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

class _LutChip extends StatelessWidget {
  const _LutChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? WhipcutTheme.amber.withValues(alpha: 0.16)
              : WhipcutTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? WhipcutTheme.amber
                : WhipcutTheme.surfaceOutline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(
                Icons.check,
                size: 16,
                color: WhipcutTheme.amber,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected
                    ? WhipcutTheme.amber
                    : WhipcutTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks a `.cube` file, copies it into the app's `luts/` directory, and
/// records it in shared_preferences metadata.
Future<void> _importLut(WidgetRef ref) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['cube'],
  );
  if (result == null || result.files.isEmpty) return;
  final srcPath = result.files.first.path;
  if (srcPath == null || srcPath.isEmpty) return;

  final docs = await getApplicationDocumentsDirectory();
  final lutsDir =
      Directory('${docs.path}${Platform.pathSeparator}luts');
  if (!await lutsDir.exists()) {
    await lutsDir.create(recursive: true);
  }

  final fileName = srcPath.split(Platform.pathSeparator).last;
  var dest =
      File('${lutsDir.path}${Platform.pathSeparator}$fileName');
  if (await dest.exists()) {
    // De-duplicate: keep both copies with a numbered suffix.
    final stem =
        fileName.replaceAll(RegExp(r'\.cube$', caseSensitive: false), '');
    var n = 2;
    while (await dest.exists()) {
      dest = File(
          '${lutsDir.path}${Platform.pathSeparator}${stem}_$n.cube');
      n++;
    }
  }
  await File(srcPath).copy(dest.path);

  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kLutPrefsKey);
  final List<dynamic> stored =
      raw == null || raw.isEmpty ? <dynamic>[] : List<dynamic>.from(
          jsonDecode(raw) as List);
  stored.removeWhere(
      (e) => (e as Map<String, dynamic>)['path'] == dest.path);
  // Prune entries whose files vanished, then append the new one.
  final pruned = <Map<String, dynamic>>[];
  for (final e in stored) {
    final map = Map<String, dynamic>.from(e as Map);
    final path = map['path'];
    if (path is String &&
        path.isNotEmpty &&
        await File(path).exists()) {
      pruned.add(map);
    }
  }
  pruned.add(<String, dynamic>{
    'name': dest.path
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'\.cube$', caseSensitive: false), ''),
    'path': dest.path,
  });
  await prefs.setString(_kLutPrefsKey, jsonEncode(pruned));

  ref.invalidate(_lutListProvider);
}
