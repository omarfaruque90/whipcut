// Tests for the in-app updater (Khorcha-style update checker).
//
// Covers: version normalization/comparison, release-JSON parsing,
// fetch failure modes, APK download against a local HTTP server,
// the native MethodChannel contract, the once-per-day prompt gate,
// and the update dialog UI.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whipcut/features/update/update_dialog.dart';
import 'package:whipcut/features/update/update_providers.dart';
import 'package:whipcut/features/update/update_service.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';

const _releaseJson = {
  'tag_name': 'v0.2',
  'body': 'Bug fixes and faster export.',
  'assets': [
    {
      'name': 'app-arm64-v8a-release.apk',
      'browser_download_url': 'https://example.com/app.apk',
    },
    {
      'name': 'checksums.txt',
      'browser_download_url': 'https://example.com/checksums.txt',
    },
  ],
};

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService({required this.release, this.current = '0.1'});

  final ReleaseInfo? release;
  final String current;

  @override
  Future<String> getInstalledVersion() async => current;

  @override
  Future<ReleaseInfo?> fetchLatestRelease({
    Future<String> Function(Uri uri)? fetchBody,
  }) async =>
      release;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeVersion', () {
    test('strips v prefix, whitespace, pre-release and build metadata', () {
      expect(UpdateService.normalizeVersion('v0.1'), '0.1');
      expect(UpdateService.normalizeVersion('V2.3.4'), '2.3.4');
      expect(UpdateService.normalizeVersion('  v1.2  '), '1.2');
      expect(UpdateService.normalizeVersion('1.0.0+5'), '1.0.0');
      expect(UpdateService.normalizeVersion('1.2.3-beta'), '1.2.3');
      expect(UpdateService.normalizeVersion('3.0'), '3.0');
    });
  });

  group('compareVersions', () {
    test('equal versions compare as 0', () {
      expect(UpdateService.compareVersions('1.0.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('v0.1', '0.1.0'), 0);
      expect(UpdateService.compareVersions('1.0', '1.0.0'), 0);
    });

    test('numeric (not lexicographic) segment comparison', () {
      expect(UpdateService.compareVersions('0.2', '0.1'), greaterThan(0));
      expect(UpdateService.compareVersions('0.1', '0.2'), lessThan(0));
      expect(UpdateService.compareVersions('2.0', '10.0'), lessThan(0));
      expect(UpdateService.compareVersions('1.0.10', '1.0.9'), greaterThan(0));
      expect(UpdateService.compareVersions('0.1.9', '0.2'), lessThan(0));
    });
  });

  group('isUpdateAvailable', () {
    test('true only when the release is strictly newer', () {
      expect(UpdateService.isUpdateAvailable('0.1', '0.2'), isTrue);
      expect(UpdateService.isUpdateAvailable('0.1', '0.1'), isFalse);
      expect(UpdateService.isUpdateAvailable('1.0.0', '0.2'), isFalse);
      expect(UpdateService.isUpdateAvailable('0.9.9', '1.0.0'), isTrue);
    });
  });

  group('parseReleaseJson', () {
    test('extracts version, notes and the .apk asset url', () {
      final info = UpdateService.parseReleaseJson(_releaseJson);
      expect(info, isNotNull);
      expect(info!.tagName, 'v0.2');
      expect(info.version, '0.2');
      expect(info.notes, 'Bug fixes and faster export.');
      expect(info.apkUrl, 'https://example.com/app.apk');
    });

    test('null when there is no .apk asset', () {
      expect(
        UpdateService.parseReleaseJson({
          'tag_name': 'v0.2',
          'body': '',
          'assets': [],
        }),
        isNull,
      );
    });

    test('null when the tag is missing', () {
      expect(UpdateService.parseReleaseJson({'assets': []}), isNull);
    });

    test('empty body becomes empty notes', () {
      final info = UpdateService.parseReleaseJson({
        'tag_name': 'v0.3',
        'assets': [
          {'name': 'a.apk', 'browser_download_url': 'https://x/y.apk'},
        ],
      });
      expect(info, isNotNull);
      expect(info!.notes, isEmpty);
    });
  });

  group('fetchLatestRelease', () {
    test('returns the parsed release on success', () async {
      final service = UpdateService();
      final info = await service.fetchLatestRelease(
        fetchBody: (_) async =>
            '{"tag_name":"v0.2","body":"x","assets":[{"name":"a.apk","browser_download_url":"https://x/y.apk"}]}',
      );
      expect(info, isNotNull);
      expect(info!.version, '0.2');
    });

    test('null on network failure (silent skip)', () async {
      final service = UpdateService();
      final info = await service.fetchLatestRelease(
        fetchBody: (_) => throw const SocketException('offline'),
      );
      expect(info, isNull);
    });

    test('null on malformed JSON', () async {
      final service = UpdateService();
      final info = await service.fetchLatestRelease(
        fetchBody: (_) async => 'not json',
      );
      expect(info, isNull);
    });
  });

  group('downloadApk', () {
    test('streams bytes to a file and reports progress', () async {
      final payload = List<int>.generate(4096, (i) => i % 256);
      final dir = await Directory.systemTemp.createTemp('whipcut_update_test');
      var lastReceived = 0;
      var lastTotal = -1;
      try {
        final service = UpdateService();
        final file = await service.downloadApk(
          'https://example.com/app.apk',
          saveDir: dir,
          fetchStream: (_) async => DownloadSource(
            stream: Stream.value(payload),
            totalBytes: payload.length,
          ),
          onProgress: (received, total) {
            lastReceived = received;
            lastTotal = total;
          },
        );
        expect(await file.readAsBytes(), payload);
        expect(lastReceived, payload.length);
        expect(lastTotal, payload.length);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('throws when the stream fails', () async {
      final dir = await Directory.systemTemp.createTemp('whipcut_update_test');
      try {
        final service = UpdateService();
        expect(
          () => service.downloadApk(
            'https://example.com/app.apk',
            saveDir: dir,
            fetchStream: (_) => throw const SocketException('offline'),
          ),
          throwsA(isA<SocketException>()),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('native channel contract', () {
    const channel = MethodChannel('whipcut/update');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'getAppVersion') return '9.9.9';
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('getInstalledVersion reads the native version', () async {
      expect(await UpdateService().getInstalledVersion(), '9.9.9');
    });

    test('installApk sends the file path to the native installer', () async {
      await UpdateService()
          .installApk(File('/tmp/whipcut-update.apk'));
      expect(calls, hasLength(1));
      expect(calls.single.method, 'installApk');
      expect(calls.single.arguments['path'], '/tmp/whipcut-update.apk');
    });
  });

  group('UpdateController prompt gate', () {
    const release = ReleaseInfo(
      tagName: 'v0.2',
      version: '0.2',
      notes: 'notes',
      apkUrl: 'https://example.com/a.apk',
    );

    ProviderContainer containerWith(ReleaseInfo? r, {String current = '0.1'}) {
      return ProviderContainer(overrides: [
        updateServiceProvider.overrideWithValue(
          _FakeUpdateService(release: r, current: current),
        ),
      ]);
    }

    test('startup check surfaces the update once, then snoozes for today',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = containerWith(release);
      addTearDown(container.dispose);

      await container.read(updateControllerProvider.notifier).checkOnStartup();
      expect(container.read(updateControllerProvider).available, isNotNull);

      // Dismiss ("Later") and re-run in the same session: no re-prompt.
      container.read(updateControllerProvider.notifier).dismiss();
      await container.read(updateControllerProvider.notifier).checkOnStartup();
      expect(container.read(updateControllerProvider).available, isNull);

      // A fresh controller (e.g. app restart) still skips: prompted today.
      final container2 = containerWith(release);
      addTearDown(container2.dispose);
      await container2.read(updateControllerProvider.notifier).checkOnStartup();
      expect(container2.read(updateControllerProvider).available, isNull);
    });

    test('no prompt when already up to date or check fails', () async {
      SharedPreferences.setMockInitialValues({});
      final upToDate = containerWith(release, current: '0.2');
      addTearDown(upToDate.dispose);
      await upToDate.read(updateControllerProvider.notifier).checkOnStartup();
      expect(upToDate.read(updateControllerProvider).available, isNull);

      final failed = containerWith(null);
      addTearDown(failed.dispose);
      await failed.read(updateControllerProvider.notifier).checkOnStartup();
      expect(failed.read(updateControllerProvider).available, isNull);
    });

    test('manual check returns the release when an update exists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = containerWith(release);
      addTearDown(container.dispose);
      final info =
          await container.read(updateControllerProvider.notifier).checkManually();
      expect(info, isNotNull);
      expect(info!.version, '0.2');
      expect(container.read(updateControllerProvider).checking, isFalse);
    });
  });

  group('update dialog', () {
    const info = ReleaseInfo(
      tagName: 'v0.2',
      version: '0.2',
      notes: 'Bug fixes',
      apkUrl: 'https://example.com/a.apk',
    );

    Future<void> pumpDialogHost(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final go = await showUpdateAvailableDialog(context, info);
                  // Surface the choice for the test.
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('chose:$go')),
                  );
                },
                child: const Text('open dialog'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows version, notes, Update and Later', (tester) async {
      await pumpDialogHost(tester);
      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();

      expect(find.text('New version available'), findsOneWidget);
      expect(
          find.text('Whipcut 0.2 is ready to install.'), findsOneWidget);
      expect(find.text("What's new"), findsOneWidget);
      expect(find.text('Bug fixes'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
    });

    testWidgets('Later dismisses without choosing update', (tester) async {
      await pumpDialogHost(tester);
      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      expect(find.text('New version available'), findsNothing);
      expect(find.text('chose:false'), findsOneWidget);
    });
  });
}
