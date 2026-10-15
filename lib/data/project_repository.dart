import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whipcut/models/project.dart';

/// File-backed persistence for [WhipcutProject]s.
///
/// Owned by Agent B (projects/data). Each project is stored as one JSON file
/// at `whipcut_projects/<id>.json` inside the app documents directory.
class ProjectRepository {
  static const String _dirName = 'whipcut_projects';

  Future<Directory> _projectsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Loads every saved project. Corrupt files are skipped, never fatal.
  Future<List<WhipcutProject>> loadProjects() async {
    final dir = await _projectsDir();
    final entries = await dir.list().toList();
    final projects = <WhipcutProject>[];
    for (final entry in entries) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final raw = await entry.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        projects.add(WhipcutProject.fromJson(json));
      } catch (_) {
        // Skip a corrupt file rather than failing the whole list.
        continue;
      }
    }
    return projects;
  }

  /// Persists [project], bumping its [WhipcutProject.updatedAt] timestamp.
  Future<void> saveProject(WhipcutProject project) async {
    final dir = await _projectsDir();
    final updated = project.copyWith(updatedAt: DateTime.now());
    final file = File('${dir.path}${Platform.pathSeparator}${project.id}.json');
    await file.writeAsString(jsonEncode(updated.toJson()));
  }

  /// Deletes the saved project with [id]. No-op if it does not exist.
  Future<void> deleteProject(String id) async {
    final dir = await _projectsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$id.json');
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Notifier behind [projectListProvider].
///
/// Loads the saved projects at construction, keeps the list sorted by
/// `updatedAt` (newest first), and refreshes after every add/delete.
class ProjectListNotifier extends StateNotifier<AsyncValue<List<WhipcutProject>>> {
  ProjectListNotifier(this._repo) : super(const AsyncLoading()) {
    load();
  }

  final ProjectRepository _repo;

  Future<void> load() async {
    state = const AsyncLoading();
    try {
      final projects = await _repo.loadProjects();
      projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = AsyncData(projects);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Alias for [load] for UI-triggered refreshes (e.g. returning from editor).
  Future<void> refresh() => load();

  /// Saves [project] (bumps `updatedAt`) and reloads the list.
  Future<void> add(WhipcutProject project) async {
    await _repo.saveProject(project);
    await load();
  }

  /// Deletes the project with [id] and reloads the list.
  Future<void> delete(String id) async {
    await _repo.deleteProject(id);
    await load();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Singleton access to the file-backed [ProjectRepository].
final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository();
});

/// The saved-project list (newest first), with load/add/delete/refresh.
final projectListProvider =
    StateNotifierProvider<ProjectListNotifier, AsyncValue<List<WhipcutProject>>>((ref) {
  return ProjectListNotifier(ref.watch(projectRepositoryProvider));
});

/// The project currently open in the editor, if any.
final currentProjectProvider = StateProvider<WhipcutProject?>((ref) => null);
