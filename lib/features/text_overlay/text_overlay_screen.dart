import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whipcut/core/theme.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';
import 'package:whipcut/models/text_overlay.dart';

// Integration: models/project.dart + data/project_repository.dart (Agent B,
// landed) and models/timeline.dart (Agent C, landed): TrackType,
// TimelineTrack (id, type, clips, copyWith), TimelineClip (id, mediaPath,
// start, duration, sourceStart, speed, reversed, volume, fadeIn, fadeOut,
// colorAdjust, copyWith), TimelineProject (tracks, textOverlays, duration,
// copyWith).
// ---------------------------------------------------------------------------
import 'package:whipcut/models/project.dart';
import 'package:whipcut/data/project_repository.dart';

/// Text overlay management for a project.
///
/// NOTE (export): overlays are burned into the video at export time via
/// ffmpeg `drawtext`; the in-app preview does not render them.
class TextOverlayScreen extends ConsumerWidget {
  const TextOverlayScreen({super.key, required this.project});

  final WhipcutProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overlays = project.timeline.textOverlays;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.text)),
      body: overlays.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.title, size: 56, color: WhipcutTheme.textSecondary),
                  const SizedBox(height: 12),
                  Text(l10n.noTextOverlays, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: overlays.length,
              itemBuilder: (context, index) => _OverlayCard(
                overlay: overlays[index],
                onEdit: () => _openEditor(context, ref, overlays[index]),
                onDelete: () => _deleteOverlay(context, ref, overlays[index]),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, null),
        icon: const Icon(Icons.add),
        label: Text(l10n.addText),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref, TextOverlay? existing) async {
    final result = await showModalBottomSheet<TextOverlay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WhipcutTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _TextOverlayEditor(
          existing: existing,
          maxDuration: project.timeline.duration,
        ),
      ),
    );
    if (result == null || !context.mounted) return;

    final overlays = List<TextOverlay>.of(project.timeline.textOverlays);
    final idx = overlays.indexWhere((o) => o.id == result.id);
    if (idx >= 0) {
      overlays[idx] = result;
    } else {
      overlays.add(result);
    }
    await _persist(ref, overlays);
  }

  Future<void> _deleteOverlay(BuildContext context, WidgetRef ref, TextOverlay overlay) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(overlay.text, maxLines: 2, overflow: TextOverflow.ellipsis),
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
    final overlays =
        project.timeline.textOverlays.where((o) => o.id != overlay.id).toList();
    await _persist(ref, overlays);
  }

  Future<void> _persist(WidgetRef ref, List<TextOverlay> overlays) async {
    final updated = project.copyWith(
      timeline: project.timeline.copyWith(textOverlays: overlays),
      updatedAt: DateTime.now(),
    );
    await ref.read(projectRepositoryProvider).saveProject(updated);
    ref.read(currentProjectProvider.notifier).state = updated;
  }
}

/// One overlay row: live-styled preview, timing label, edit + delete.
class _OverlayCard extends StatelessWidget {
  const _OverlayCard({
    required this.overlay,
    required this.onEdit,
    required this.onDelete,
  });

  final TextOverlay overlay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text(
          overlay.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            color: Color(overlay.color),
            fontWeight: overlay.bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        subtitle: Text(
          '${_fmt(overlay.start)} – ${_fmt(overlay.start + overlay.duration)}'
          '  •  ${l10n.fontSize}: ${overlay.fontSize.round()}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: l10n.done,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: l10n.delete,
              icon: const Icon(Icons.delete_outline, color: WhipcutTheme.danger),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Add/edit bottom sheet: text field, font-size slider, color swatches,
/// position presets, bold toggle, start/duration sliders.
class _TextOverlayEditor extends StatefulWidget {
  const _TextOverlayEditor({required this.existing, required this.maxDuration});

  final TextOverlay? existing;
  final double maxDuration;

  @override
  State<_TextOverlayEditor> createState() => _TextOverlayEditorState();
}

class _TextOverlayEditorState extends State<_TextOverlayEditor> {
  static const _swatches = <int>[
    0xFFFFFFFF, // white
    0xFF000000, // black
    0xFFF5A623, // amber
    0xFFE5484D, // red
    0xFF4CC9F0, // cyan
  ];

  late final TextEditingController _textController;
  late double _fontSize;
  late int _color;
  late double _y;
  late bool _bold;
  late double _start;
  late double _duration;

  double get _timelineMax => widget.maxDuration > 0 ? widget.maxDuration : 60;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _textController = TextEditingController(text: e?.text ?? '');
    _fontSize = e?.fontSize ?? 48;
    _color = e?.color ?? 0xFFFFFFFF;
    _y = e?.y ?? 0.5;
    _bold = e?.bold ?? false;
    _start = e?.start ?? 0;
    _duration = e?.duration ?? 2;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preset = _y <= 0.2 ? 0 : (_y >= 0.8 ? 2 : 1);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? l10n.addText : l10n.text,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            // Live preview
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: WhipcutTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: WhipcutTheme.surfaceOutline),
              ),
              alignment: Alignment(0, _y * 2 - 1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _textController.text.isEmpty ? l10n.textContent : _textController.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: (_fontSize / 3).clamp(16, 40).toDouble(),
                    color: Color(_color),
                    fontWeight: _bold ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              maxLines: 2,
              style: const TextStyle(color: WhipcutTheme.textPrimary),
              decoration: InputDecoration(
                labelText: l10n.textContent,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _LabeledRow(label: '${l10n.fontSize}: ${_fontSize.round()}'),
            Slider(
              value: _fontSize,
              min: 24,
              max: 120,
              divisions: 32,
              label: _fontSize.round().toString(),
              onChanged: (v) => setState(() => _fontSize = v),
            ),
            _LabeledRow(label: l10n.textColor),
            const SizedBox(height: 8),
            Row(
              children: _swatches.map((c) {
                final selected = c == _color;
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? WhipcutTheme.amber : WhipcutTheme.surfaceOutline,
                        width: selected ? 3 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _LabeledRow(label: l10n.position),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                    value: 0, label: Text(l10n.top), icon: const Icon(Icons.vertical_align_top)),
                ButtonSegment(
                    value: 1,
                    label: Text(l10n.center),
                    icon: const Icon(Icons.vertical_align_center)),
                ButtonSegment(
                    value: 2,
                    label: Text(l10n.bottom),
                    icon: const Icon(Icons.vertical_align_bottom)),
              ],
              selected: {preset},
              onSelectionChanged: (sel) => setState(() {
                _y = switch (sel.first) { 0 => 0.15, 2 => 0.85, _ => 0.5 };
              }),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.bold),
              value: _bold,
              onChanged: (v) => setState(() => _bold = v),
            ),
            _LabeledRow(label: '${l10n.timeline}: ${_fmt(_start)}'),
            Slider(
              value: _start.clamp(0, _timelineMax).toDouble(),
              min: 0,
              max: _timelineMax,
              onChanged: (v) => setState(() => _start = v),
            ),
            _LabeledRow(label: '${l10n.duration}: ${_fmt(_duration)}'),
            Slider(
              value: _duration.clamp(0.5, _timelineMax).toDouble(),
              min: 0.5,
              max: _timelineMax,
              onChanged: (v) => setState(() => _duration = v),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _textController.text.trim().isEmpty ? null : _save,
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final e = widget.existing;
    final overlay = e == null
        ? TextOverlay.create(
            text: _textController.text.trim(),
            fontSize: _fontSize,
            color: _color,
            x: 0.5,
            y: _y,
            start: _start,
            duration: _duration,
            bold: _bold,
          )
        : e.copyWith(
            text: _textController.text.trim(),
            fontSize: _fontSize,
            color: _color,
            y: _y,
            start: _start,
            duration: _duration,
            bold: _bold,
          );
    Navigator.of(context).pop(overlay);
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      );
}

String _fmt(double seconds) {
  final s = seconds.round();
  final m = s ~/ 60;
  return '$m:${(s % 60).toString().padLeft(2, '0')}';
}
