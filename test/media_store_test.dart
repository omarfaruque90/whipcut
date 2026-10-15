import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:whipcut/features/editor/editor_providers.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.docsPath);

  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('copyPickedVideoToAppStorage', () {
    late Directory docsDir;
    late PathProviderPlatform oldPlatform;

    setUp(() async {
      docsDir =
          await Directory.systemTemp.createTemp('whipcut_docs_');
      oldPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
    });

    tearDown(() async {
      PathProviderPlatform.instance = oldPlatform;
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    test('copies the picked file into whipcut_media and keeps extension',
        () async {
      final source = File('${docsDir.path}/source_clip.mp4');
      await source.writeAsBytes(List<int>.generate(256, (i) => i % 256));

      final targetPath = await copyPickedVideoToAppStorage(source.path);

      expect(targetPath, startsWith('${docsDir.path}/whipcut_media/'));
      expect(targetPath, endsWith('.mp4'));
      final target = File(targetPath);
      expect(await target.exists(), isTrue);
      expect(await target.length(), await source.length());
      // Source untouched.
      expect(await source.exists(), isTrue);
    });

    test('two imports of the same file get distinct targets', () async {
      final source = File('${docsDir.path}/clip.mov');
      await source.writeAsBytes([1, 2, 3]);

      final first = await copyPickedVideoToAppStorage(source.path);
      final second = await copyPickedVideoToAppStorage(source.path);

      expect(first, isNot(equals(second)));
      expect(first, endsWith('.mov'));
      expect(second, endsWith('.mov'));
    });

    test('throws when the picked file does not exist', () async {
      await expectLater(
        copyPickedVideoToAppStorage('${docsDir.path}/missing.mp4'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
