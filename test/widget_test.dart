// Whipcut smoke test — owned by the scaffold agent.
// Verifies the app boots into the projects screen with localization wired.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whipcut/data/project_repository.dart';
import 'package:whipcut/features/onboarding/onboarding_providers.dart';
import 'package:whipcut/features/onboarding/onboarding_screen.dart';
import 'package:whipcut/features/projects/projects_screen.dart';
import 'package:whipcut/main.dart';
import 'package:whipcut/models/project.dart';

/// In-memory repository so the test never touches the platform
/// `path_provider` channel (whose future never completes under flutter_test,
/// which left the projects screen on its loading spinner forever and made
/// `pumpAndSettle` time out).
class _FakeProjectRepository extends ProjectRepository {
  @override
  Future<List<WhipcutProject>> loadProjects() async => const [];
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        projectRepositoryProvider
            .overrideWithValue(_FakeProjectRepository()),
      ],
      child: const WhipcutApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('First launch shows the onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpApp(tester);

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Welcome to Whipcut'), findsOneWidget);
  });

  testWidgets('App boots to the projects screen after onboarding',
      (tester) async {
    SharedPreferences.setMockInitialValues({onboardingDoneKey: true});
    await _pumpApp(tester);

    expect(find.byType(ProjectsScreen), findsOneWidget);
    // App bar shows the localized app name.
    expect(find.text('Whipcut'), findsOneWidget);
  });
}
