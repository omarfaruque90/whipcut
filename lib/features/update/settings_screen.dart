import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';

import 'update_dialog.dart';
import 'update_providers.dart';

/// Settings + About screen.
///
/// Owned by the update feature: hosts the manual "Check for updates"
/// action and the app version row.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final version = ref.watch(installedVersionProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.movie_filter_outlined, size: 64),
          const SizedBox(height: 12),
          Center(
            child: Text(
              l10n.appName,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: version.when(
              data: (v) => Text(
                'v$v',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              loading: () => const SizedBox.shrink(),
              error: (error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          Consumer(
            builder: (context, ref, _) {
              final checking = ref.watch(
                  updateControllerProvider.select((s) => s.checking));
              return ListTile(
                leading: const Icon(Icons.system_update_outlined),
                title: Text(l10n.checkForUpdates),
                trailing: checking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: checking ? null : () => _manualCheck(context, ref),
              );
            },
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Future<void> _manualCheck(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);

    // Blocking "checking" indicator.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(l10n.checkingForUpdates)),
          ],
        ),
      ),
    );

    final info =
        await ref.read(updateControllerProvider.notifier).checkManually();

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close "checking"

    if (info != null) {
      final go = await showUpdateAvailableDialog(context, info);
      ref.read(updateControllerProvider.notifier).dismiss();
      if (go && context.mounted) {
        await showDownloadProgressDialog(context, ref, info);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.upToDate)),
      );
    }
  }
}
