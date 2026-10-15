import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-wide locale, toggled from the projects screen app bar.
///
/// Moved here (integration, 2026-10-15) so `main.dart` can wire it into
/// `MaterialApp(locale: ...)` without importing from a feature module.
/// Previously lived in `features/projects/projects_screen.dart`.
final localeProvider = StateProvider<Locale>((ref) => const Locale('en'));
