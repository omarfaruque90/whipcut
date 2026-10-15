import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:whipcut/core/locale_provider.dart';
import 'package:whipcut/core/theme.dart';
import 'package:whipcut/data/project_repository.dart';
import 'package:whipcut/features/editor/editor_screen.dart';
import 'package:whipcut/features/update/settings_screen.dart';
import 'package:whipcut/features/update/update_dialog.dart';
import 'package:whipcut/features/update/update_providers.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';
import 'package:whipcut/models/project.dart';
import 'package:whipcut/models/timeline.dart';

/// Home screen — saved video projects.
///
/// Owned by Agent B (projects/data). Shows the project list with thumbnail
/// placeholders, the new-project flow, and delete. Tapping a project sets
/// [currentProjectProvider] and opens [EditorScreen] (Agent C).
///
/// NOTE (integration, 2026-10-15): the locale toggle drives [localeProvider]
/// (in `core/locale_provider.dart`), which `main.dart` wires into
/// `MaterialApp(locale: ...)`, so the whole app follows the toggle. The old
/// local `Localizations.override` was removed once that wiring landed.
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const _ProjectsBody();
}

class _ProjectsBody extends ConsumerWidget {
  const _ProjectsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    final projects = ref.watch(projectListProvider);

    // In-app update check (Khorcha-style): one prompt per day, silent on
    // failure/offline. The controller is idempotent across rebuilds.
    ref.listen(updateControllerProvider, (prev, next) {
      final info = next.available;
      if (info != null && prev?.available == null && context.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!context.mounted) return;
          final go = await showUpdateAvailableDialog(context, info);
          ref.read(updateControllerProvider.notifier).dismiss();
          if (go && context.mounted) {
            await showDownloadProgressDialog(context, ref, info);
          }
        });
      }
    });
    ref.read(updateControllerProvider.notifier).checkOnStartup();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appName),
        actions: [
          // Settings / About (manual update check lives here).
          IconButton(
            tooltip: l10n.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          // Language toggle: EN <-> BN.
          TextButton(
            onPressed: () {
              ref.read(localeProvider.notifier).state =
                  locale.languageCode == 'en' ? const Locale('bn') : const Locale('en');
            },
            child: Text(
              locale.languageCode == 'en' ? 'বাং' : 'EN',
              style: const TextStyle(
                color: WhipcutTheme.amber,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ProjectsError(onRetry: () {
          ref.read(projectListProvider.notifier).refresh();
        }),
        data: (list) {
          if (list.isEmpty) {
            return _EmptyProjects(onCreate: () => _showNewProjectDialog(context));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Text(
                      l10n.myProjects,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: WhipcutTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${list.length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  itemCount: list.length,
                  itemBuilder: (context, index) =>
                      _ProjectCard(project: list[index]),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewProjectDialog(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.newProject),
      ),
    );
  }
}

/// Opens a project: records it as current and pushes the editor (Agent C).
Future<void> _openProject(BuildContext context, WidgetRef ref, WhipcutProject project) async {
  ref.read(currentProjectProvider.notifier).state = project;
  final navigator = Navigator.of(context);
  await navigator.push(
    MaterialPageRoute(builder: (_) => EditorScreen(project: project)),
  );
  // The editor may have saved changes — refresh ordering/timestamps.
  await ref.read(projectListProvider.notifier).refresh();
}

/// Delete confirmation used by both long-press and swipe-to-delete.
Future<bool> _confirmDelete(
    BuildContext context, AppLocalizations l10n, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.deleteProject),
      content: Text(l10n.confirmDelete),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: WhipcutTheme.danger),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// A single saved project: thumbnail placeholder, name, aspect, updated date.
class _ProjectCard extends ConsumerWidget {
  const _ProjectCard({required this.project});

  final WhipcutProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    Future<void> delete() async {
      final ok = await _confirmDelete(context, l10n, project.name);
      if (!ok || !context.mounted) return;
      await ref.read(projectListProvider.notifier).delete(project.id);
      if (ref.read(currentProjectProvider)?.id == project.id) {
        ref.read(currentProjectProvider.notifier).state = null;
      }
    }

    return Dismissible(
      key: ValueKey(project.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context, l10n, project.name),
      onDismissed: (_) {
        ref.read(projectListProvider.notifier).delete(project.id);
        if (ref.read(currentProjectProvider)?.id == project.id) {
          ref.read(currentProjectProvider.notifier).state = null;
        }
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: WhipcutTheme.danger,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openProject(context, ref, project),
          onLongPress: delete,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Thumbnail placeholder shaped like the project's aspect ratio.
                SizedBox(
                  width: 96,
                  child: AspectRatio(
                    aspectRatio: project.aspectRatio.ratio,
                    child: Container(
                      decoration: BoxDecoration(
                        color: WhipcutTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: WhipcutTheme.surfaceOutline),
                      ),
                      child: const Icon(
                        Icons.movie_outlined,
                        color: WhipcutTheme.amber,
                        size: 32,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        project.name,
                        style: textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: WhipcutTheme.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: WhipcutTheme.amber.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              project.aspectRatio.label,
                              style: const TextStyle(
                                color: WhipcutTheme.amber,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              DateFormat.yMMMd().format(project.updatedAt),
                              style: textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: WhipcutTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty state with a friendly CTA.
class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.movie_creation_outlined,
              size: 80,
              color: WhipcutTheme.amber,
            ),
            const SizedBox(height: 20),
            Text(
              l10n.noProjects,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(l10n.createNewProject),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error state with a retry button.
class _ProjectsError extends StatelessWidget {
  const _ProjectsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 56,
            color: WhipcutTheme.danger,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Shows the new-project dialog.
void _showNewProjectDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const _NewProjectDialog(),
  );
}

/// New-project dialog: name field + aspect ratio preset chips.
class _NewProjectDialog extends ConsumerStatefulWidget {
  const _NewProjectDialog();

  @override
  ConsumerState<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends ConsumerState<_NewProjectDialog> {
  final _nameController = TextEditingController();
  AspectRatioPreset _preset = AspectRatioPreset.r16x9;
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _creating) return;
    setState(() => _creating = true);

    final now = DateTime.now();
    final project = WhipcutProject(
      id: const Uuid().v4(),
      name: name,
      aspectRatio: _preset,
      createdAt: now,
      updatedAt: now,
      timeline: TimelineProject(tracks: [], textOverlays: []),
    );

    await ref.read(projectListProvider.notifier).add(project);
    if (!mounted) return;
    Navigator.of(context).pop(); // Close the dialog first.
    await _openProject(context, ref, project);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canCreate = _nameController.text.trim().isNotEmpty && !_creating;

    return AlertDialog(
      title: Text(l10n.newProject),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.projectName,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.aspectRatio,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in AspectRatioPreset.values)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: _preset == preset,
                    onSelected: (_) => setState(() => _preset = preset),
                    selectedColor: WhipcutTheme.amber,
                    labelStyle: TextStyle(
                      color: _preset == preset
                          ? Colors.black
                          : WhipcutTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: canCreate ? _create : null,
          child: _creating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.createProject),
        ),
      ],
    );
  }
}
