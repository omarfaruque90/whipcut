# Whipcut

A pro-focused mobile video editor for cinematographers and content creators —
color science, export quality, and text animation first. **Phase 1 MVP.**

- Package: `com.whipcut.app` · minSdk 24 · Android only
- Stack: Flutter (stable) + Riverpod + FFmpeg (`ffmpeg_kit_flutter_new`)
- UI language: English + Bangla (`lib/l10n`, generated via `flutter gen-l10n`)
- Theme: dark pro theme, amber `#f5a623` accent (`lib/core/theme.dart`)

## Build commands

```bash
source ~/workspace/whipcut-env.sh   # required in EVERY shell (Flutter/Java/Android SDK)
cd ~/workspace/whipcut

flutter pub get        # install dependencies
flutter gen-l10n       # regenerate localizations after editing lib/l10n/*.arb
flutter analyze        # must be CLEAN before any handoff
flutter test           # widget smoke test
flutter build apk --release   # release APK (debug-signed until release key added)
```

Toolchain lives in `~/workspace` (never reinstall):
`flutter-sdk`, `android-sdk`, `jdk17`, configured by `~/workspace/whipcut-env.sh`.

## Module ownership

**Scaffold agent owns (do not touch without parent approval):**
`pubspec.yaml`, `android/`, `lib/main.dart`, `lib/core/`, `lib/l10n/`,
`l10n.yaml`, `flutter_launcher_icons.yaml`, `README.md`.

Feature agents are **forbidden** from editing `pubspec.yaml` — all Phase 1
packages are pre-installed. Need another package? Hand the exact name +
version to the parent agent.

| Directory | Owner | Notes |
|---|---|---|
| `lib/features/projects/` | projects agent | Project list, new-project flow, media import (`image_picker`, `file_picker`) |
| `lib/features/editor/` | editor agent | Timeline, clip trim/split, preview (`video_player`) |
| `lib/features/adjust/` | adjust agent | Color correction filters |
| `lib/features/text_overlay/` | text agent | Animated text overlays |
| `lib/features/audio/` | audio agent | Music, voice-over (`record`), one-tap Voice Enhance |
| `lib/features/export/` | export agent | FFmpeg render pipeline — see below |
| `lib/models/` | data agent | Clip/project data classes |
| `lib/data/` | data agent | Repositories, persistence (`shared_preferences`, `path_provider`) |
| `lib/widgets/` | shared | Reusable widgets — keep generic, no feature logic |
| `lib/core/` | scaffold | Theme, constants, shared utilities |

## Key integration notes for feature agents

- **Localization:** `import 'package:whipcut/l10n/generated/app_localizations.dart';`
  then `final l10n = AppLocalizations.of(context);`. Add keys to **both**
  `app_en.arb` and `app_bn.arb`, then run `flutter gen-l10n`.
- **Theme:** `WhipcutTheme.darkTheme` is already on `MaterialApp`. Use
  `WhipcutTheme.amber`, `.background`, `.surface`, `.textPrimary`, etc. —
  no ad-hoc colors.
- **State:** Riverpod. `main.dart` wraps the app in `ProviderScope`.
- **Export engine:** `ffmpeg_kit_flutter_new` v4.6.7 (maintained community
  fork of the archived `ffmpeg_kit_flutter`; same API):
  ```dart
  import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
  final session = await FFmpegKit.execute('-i input.mp4 -c:v libx264 out.mp4');
  final rc = await session.getReturnCode();
  ```
  Probing: `package:ffmpeg_kit_flutter_new/ffprobe_kit.dart` → `FFprobeKit`.
- **Launcher icon:** source `assets/images/app_icon.webp`; regenerate with
  `dart run flutter_launcher_icons` (config: `flutter_launcher_icons.yaml`).
- **App ID / namespace:** `com.whipcut.app` (both `applicationId` and
  `namespace` in `android/app/build.gradle.kts`); label `Whipcut`.

## Status

Scaffold complete (2026-10-15): project created, Android config set, all
dependencies resolved, launcher icons generated, l10n (en/bn, 28 keys)
generated, dark theme + placeholder home screen, `flutter analyze` clean.
Feature work not started.
