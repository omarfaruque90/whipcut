/// Export screen — preset/custom render settings + progress UI (Agent E).
///
/// Contract: `class ExportScreen extends ConsumerWidget {
///   const ExportScreen({super.key, required this.project});
///   final WhipcutProject project; }`
///
/// Dark pro UI built on WhipcutTheme tokens only. Guards the empty timeline
/// (no video clips -> empty state instead of the export button).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whipcut/core/theme.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';
import 'package:whipcut/models/project.dart';
import 'package:whipcut/models/timeline.dart';

import 'export_engine.dart';
import 'export_providers.dart';

class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key, required this.project});

  final WhipcutProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final videoClipCount = project.timeline.tracks
        .where((t) => t.type == TrackType.video)
        .expand((t) => t.clips)
        .length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.export)),
      body: videoClipCount == 0
          ? _EmptyState(message: l10n.noClips)
          : _ExportBody(project: project),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.movie_outlined,
              size: 64,
              color: WhipcutTheme.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: WhipcutTheme.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportBody extends ConsumerWidget {
  const _ExportBody({required this.project});

  final WhipcutProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(exportConfigProvider);
    final state = ref.watch(exportControllerProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(l10n.exportPreset),
          _PresetCard(
            preset: ExportPreset.youtube4k,
            title: l10n.youtube4k,
            subtitle: '3840 \u00d7 2160 \u00b7 30 fps \u00b7 20 Mbps \u00b7 H.264',
            selected: config.preset == ExportPreset.youtube4k,
            onTap: () => ref
                .read(exportConfigProvider.notifier)
                .update((c) => c.copyWith(preset: ExportPreset.youtube4k)),
          ),
          _PresetCard(
            preset: ExportPreset.reels,
            title: l10n.reels,
            subtitle: '1080 \u00d7 1920 \u00b7 30 fps \u00b7 12 Mbps \u00b7 H.264',
            selected: config.preset == ExportPreset.reels,
            onTap: () => ref
                .read(exportConfigProvider.notifier)
                .update((c) => c.copyWith(preset: ExportPreset.reels)),
          ),
          _PresetCard(
            preset: ExportPreset.custom,
            title: l10n.custom,
            subtitle: l10n.resolution,
            selected: config.preset == ExportPreset.custom,
            onTap: () => ref
                .read(exportConfigProvider.notifier)
                .update((c) => c.copyWith(preset: ExportPreset.custom)),
          ),
          if (config.preset == ExportPreset.custom) ...[
            const SizedBox(height: 8),
            _CustomSettings(config: config),
          ],
          const SizedBox(height: 24),
          _ExportAction(project: project, state: state),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: WhipcutTheme.textSecondary,
            ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final ExportPreset preset;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? WhipcutTheme.amber : WhipcutTheme.surfaceOutline,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? WhipcutTheme.amber
                    : WhipcutTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomSettings extends ConsumerWidget {
  const _CustomSettings({required this.config});

  final ExportConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final updater = ref.read(exportConfigProvider.notifier);

    String resolutionLabel(ExportResolution r) {
      switch (r) {
        case ExportResolution.p720:
          return '720p';
        case ExportResolution.p1080:
          return '1080p';
        case ExportResolution.p2160:
          return '4K';
        case ExportResolution.original:
          return l10n.original;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.resolution,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            DropdownButtonFormField<ExportResolution>(
              initialValue: config.resolution,
              dropdownColor: WhipcutTheme.surfaceElevated,
              items: ExportResolution.values
                  .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(resolutionLabel(r)),
                      ))
                  .toList(),
              onChanged: (r) {
                if (r != null) {
                  updater.update((c) => c.copyWith(resolution: r));
                }
              },
            ),
            const SizedBox(height: 16),
            Text(l10n.fps, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              initialValue: config.fps,
              dropdownColor: WhipcutTheme.surfaceElevated,
              items: const [24, 30, 60]
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text('$f'),
                      ))
                  .toList(),
              onChanged: (f) {
                if (f != null) updater.update((c) => c.copyWith(fps: f));
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.bitrate,
                    style: Theme.of(context).textTheme.labelLarge),
                Text('${config.bitrateMbps.toStringAsFixed(0)} Mbps',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: WhipcutTheme.amber,
                          fontWeight: FontWeight.w600,
                        )),
              ],
            ),
            Slider(
              value: config.bitrateMbps,
              min: 2,
              max: 40,
              divisions: 38,
              label: '${config.bitrateMbps.toStringAsFixed(0)} Mbps',
              onChanged: (v) =>
                  updater.update((c) => c.copyWith(bitrateMbps: v)),
            ),
            const SizedBox(height: 8),
            Text(l10n.codec, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<ExportCodec>(
              segments: [
                ButtonSegment(
                    value: ExportCodec.h264, label: Text(l10n.h264)),
                ButtonSegment(
                    value: ExportCodec.h265, label: Text(l10n.h265)),
              ],
              selected: {config.codec},
              onSelectionChanged: (sel) =>
                  updater.update((c) => c.copyWith(codec: sel.first)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportAction extends ConsumerWidget {
  const _ExportAction({required this.project, required this.state});

  final WhipcutProject project;
  final ExportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(exportControllerProvider.notifier);

    switch (state.status) {
      case ExportStatus.idle:
        return ElevatedButton.icon(
          onPressed: () => controller.startExport(project),
          icon: const Icon(Icons.ios_share),
          label: Text(l10n.startExport),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        );
      case ExportStatus.running:
        final pct = (state.progress * 100).toStringAsFixed(0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.exporting,
                    style: Theme.of(context).textTheme.titleMedium),
                Text('$pct %',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: WhipcutTheme.amber,
                          fontWeight: FontWeight.w600,
                        )),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: state.progress),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => controller.cancelExport(),
              icon: const Icon(Icons.close, color: WhipcutTheme.danger),
              label: Text(l10n.cancel,
                  style: const TextStyle(color: WhipcutTheme.danger)),
            ),
          ],
        );
      case ExportStatus.done:
        return _ResultCard(
          icon: Icons.check_circle,
          iconColor: WhipcutTheme.amber,
          title: l10n.exportComplete,
          body: l10n.savedTo(state.outputPath ?? ''),
          hint: l10n.exportHint,
          actionLabel: l10n.startExport,
          onAction: controller.reset,
        );
      case ExportStatus.error:
        return _ResultCard(
          icon: Icons.error_outline,
          iconColor: WhipcutTheme.danger,
          title: l10n.exportFailed,
          body: state.errorMessage ?? '',
          hint: null,
          actionLabel: l10n.startExport,
          onAction: controller.reset,
        );
    }
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.hint,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String? hint;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: WhipcutTheme.textSecondary,
                  ),
            ),
            if (hint case final hintText?) ...[
              const SizedBox(height: 4),
              Text(
                hintText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
