import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';

import 'core/locale_provider.dart';
import 'core/theme.dart';
import 'features/projects/projects_screen.dart';

/// Whipcut entry point.
///
/// Owned by the scaffold agent. Feature agents: do NOT restructure this file.
/// Add routes/providers in your own feature modules and wire them here only
/// via the parent agent's direction.
void main() {
  runApp(const ProviderScope(child: WhipcutApp()));
}

/// App root. ConsumerWidget (integration, 2026-10-15) so the whole app —
/// projects list, editor, and all panels — follows [localeProvider], which
/// the projects screen's app-bar toggle switches between EN and BN.
class WhipcutApp extends ConsumerWidget {
  const WhipcutApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      title: 'Whipcut',
      debugShowCheckedModeBanner: false,
      theme: WhipcutTheme.darkTheme,
      darkTheme: WhipcutTheme.darkTheme,
      themeMode: ThemeMode.dark,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ProjectsScreen(),
    );
  }
}
