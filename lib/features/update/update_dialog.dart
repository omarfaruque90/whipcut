import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';

import 'update_providers.dart';
import 'update_service.dart';

/// Update prompt shown when a newer release exists.
///
/// Returns true when the user taps [Update], false on [Later]/dismiss.
Future<bool> showUpdateAvailableDialog(
    BuildContext context, ReleaseInfo info) async {
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.newVersionAvailable),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 340),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.updateAvailableMessage(info.version),
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.whatsNew,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(info.notes,
                    style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.later),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.update),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Downloads the APK with a progress bar, then fires the installer.
///
/// Pops itself when done; shows a snackbar on failure.
Future<void> showDownloadProgressDialog(
    BuildContext context, WidgetRef ref, ReleaseInfo info) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DownloadProgressDialog(info: info),
  );
}

class _DownloadProgressDialog extends ConsumerStatefulWidget {
  const _DownloadProgressDialog({required this.info});

  final ReleaseInfo info;

  @override
  ConsumerState<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState
    extends ConsumerState<_DownloadProgressDialog> {
  final ValueNotifier<double?> _progress = ValueNotifier(null);
  bool _started = false;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!_started) {
      _started = true;
      // Start after the first frame so the dialog is visible.
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
    return AlertDialog(
      title: Text(l10n.downloadingUpdate),
      content: ValueListenableBuilder<double?>(
        valueListenable: _progress,
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value == null)
              const LinearProgressIndicator()
            else
              LinearProgressIndicator(value: value.clamp(0.0, 1.0)),
            const SizedBox(height: 12),
            Text(
              value == null
                  ? '…'
                  : '${(value.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(updateControllerProvider.notifier);
    final file = await controller.downloadUpdate(
      widget.info,
      onProgress: (received, total) {
        if (total > 0) _progress.value = received / total;
      },
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.downloadFailed)),
      );
    } else {
      await controller.installUpdate(file);
    }
  }
}
