// Tests for the first-run onboarding + in-app user guide.
//
// Covers: the done-flag provider defaults to false, the onboarding
// PageView shows all five steps, Skip and Get started both write the
// flag, and the guide screen renders all steps plus the Tips section.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whipcut/features/onboarding/guide_screen.dart';
import 'package:whipcut/features/onboarding/onboarding_providers.dart';
import 'package:whipcut/features/onboarding/onboarding_screen.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';

Future<void> pumpOnboarding(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const OnboardingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('onboarding flag', () {
    test('defaults to false on first launch', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(onboardingDoneProvider.future), isFalse);
    });

    test('true after completion', () async {
      SharedPreferences.setMockInitialValues(
          {onboardingDoneKey: true});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(onboardingDoneProvider.future), isTrue);
    });
  });

  group('onboarding screen', () {
    testWidgets('shows the welcome page first', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpOnboarding(tester);

      expect(find.text('Welcome to Whipcut'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('Next advances through all five pages', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpOnboarding(tester);

      const titles = [
        'Welcome to Whipcut',
        'Start a new project',
        'Edit on the timeline',
        'Grade like a pro',
        'Export in 4K',
      ];
      for (final title in titles.skip(1)) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
      }
      // Last page shows "Get started" instead of Next/Skip.
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('Skip writes the done flag', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpOnboarding(tester);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(onboardingDoneKey), isTrue);
    });

    testWidgets('Get started on the last page writes the done flag',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpOnboarding(tester);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(onboardingDoneKey), isTrue);
    });
  });

  group('guide screen', () {
    Future<void> pumpGuide(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const GuideScreen(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders all five steps and the tips section',
        (tester) async {
      await pumpGuide(tester);

      expect(find.text('How to use'), findsOneWidget);
      for (final title in [
        '1. Welcome to Whipcut',
        '2. Start a new project',
        '3. Edit on the timeline',
        '4. Grade like a pro',
        '5. Export in 4K',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Tips'), findsOneWidget);
      expect(
          find.text('Autosave is on — drafts are saved automatically.'),
          findsOneWidget);
      expect(find.text('No watermark, ever — your exports are clean.'),
          findsOneWidget);
      expect(find.text('Works fully offline — no internet needed.'),
          findsOneWidget);
    });

    testWidgets('expanding a step shows its description', (tester) async {
      await pumpGuide(tester);

      await tester.tap(find.text('2. Start a new project'));
      await tester.pumpAndSettle();

      expect(
          find.text(
              'Tap + to create a project, pick an aspect ratio (16:9, 9:16, 1:1, 4:5), then import videos from your gallery.'),
          findsOneWidget);
    });
  });
}
