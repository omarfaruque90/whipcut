// Unit tests for the export engine's pure command builder (Agent E).
//
// These exercise buildCommand/buildArguments only — no ffprobe, no
// filesystem, no native FFmpeg calls.
import 'package:flutter_test/flutter_test.dart';
import 'package:whipcut/features/export/export_engine.dart';
import 'package:whipcut/models/color_adjust.dart';
import 'package:whipcut/models/text_overlay.dart';
import 'package:whipcut/models/timeline.dart';

TimelineClip _clip({
  String id = 'c1',
  String mediaPath = '/sdcard/vid.mp4',
  double start = 0,
  double duration = 4,
  double sourceStart = 2,
  double speed = 1,
  bool reversed = false,
  double volume = 1,
  double fadeIn = 0,
  double fadeOut = 0,
  ColorAdjust colorAdjust = ColorAdjust.identity,
}) =>
    TimelineClip(
      id: id,
      mediaPath: mediaPath,
      start: start,
      duration: duration,
      sourceStart: sourceStart,
      speed: speed,
      reversed: reversed,
      volume: volume,
      fadeIn: fadeIn,
      fadeOut: fadeOut,
      colorAdjust: colorAdjust,
    );

/// Joins the raw ffmpeg argument list (what the runner passes to
/// FFmpegKit.executeWithArgumentsAsync) — no shell quoting.
String _cmd(ExportPlan plan, ExportSettings settings, String out) =>
    buildArguments(plan, settings, out).join(' ');

void main() {
  test('full command: inputs, video chain, audio chain, drawtext, codecs',
      () {
    final clip = _clip(
      speed: 2.0,
      reversed: true,
      volume: 0.8,
      fadeIn: 0.5,
      fadeOut: 0.5,
      colorAdjust: const ColorAdjust(
        exposure: 1,
        contrast: 1.2,
        saturation: 1.1,
        temperature: 0.5,
      ),
    );
    final music = _clip(
      id: 'm1',
      mediaPath: '/sdcard/song.mp3',
      start: 1,
      duration: 6,
      sourceStart: 0,
    );
    final overlay = TextOverlay(
      id: 't1',
      text: "Hello: it's",
      fontSize: 48,
      color: 0xFFFF0000,
      x: 0.5,
      y: 0.9,
      start: 1,
      duration: 2,
      bold: true,
    );
    final plan = ExportPlan(
      videoClips: [PlannedVideoClip(clip: clip, hasAudio: true)],
      audioClips: [music],
      textOverlays: [overlay],
      totalDuration: 6,
      fontPath: '/system/fonts/Roboto-Regular.ttf',
      fontBoldPath: '/system/fonts/Roboto-Bold.ttf',
    );

    final cmd =
        _cmd(plan, ExportSettings.youtube4k(), '/out/whipcut_x.mp4');

    // Input trimming: -ss sourceStart, -t duration*speed.
    expect(cmd, contains('-ss 2 -t 8 -i /sdcard/vid.mp4'));
    // Video chain.
    expect(cmd, contains('reverse,setpts=PTS/2'));
    expect(cmd, contains('eq=brightness=0.15:contrast=1.2:saturation=1.1'));
    expect(cmd, contains('colortemperature=temperature=7500'));
    expect(cmd, contains('scale=3840:2160'));
    expect(cmd, contains('pad=3840:2160'));
    expect(cmd, contains('concat=n=1:v=1:a=0'));
    // Audio chain.
    expect(cmd, contains('atempo=2'));
    expect(cmd, contains('areverse'));
    expect(cmd, contains('volume=0.8'));
    expect(cmd, contains('afade=t=in:st=0:d=0.5'));
    expect(cmd, contains('afade=t=out:st=3.5:d=0.5'));
    expect(cmd, contains('adelay=delays=1000:all=1'));
    expect(cmd, contains('amix=inputs=2'));
    // drawtext: bold font, escaped text, ARGB color, scaled size/position.
    expect(cmd, contains("fontfile='/system/fonts/Roboto-Bold.ttf'"));
    expect(cmd, contains(r"text='Hello\: it\'s'"));
    expect(cmd, contains('fontcolor=0xFFFF0000'));
    expect(cmd, contains('fontsize=96'));
    expect(cmd, contains('x=1920:y=1944'));
    expect(cmd, contains("enable='between(t,1,3)'"));
    // Encoding.
    expect(cmd, contains('-c:v libx264'));
    expect(cmd, contains('-b:v 20M'));
    expect(cmd, contains('-r 30'));
    expect(cmd, contains('-c:a aac'));
    expect(cmd, contains('-movflags +faststart'));
    expect(cmd, endsWith('/out/whipcut_x.mp4'));
    // No watermark beyond user overlays.
    expect(cmd, isNot(contains('whipcut_logo')));
  });

  test('atempo chains cover the 0.25x-4x range', () {
    String audioFilterFor(double speed) {
      final plan = ExportPlan(
        videoClips: [
          PlannedVideoClip(clip: _clip(speed: speed), hasAudio: true)
        ],
        audioClips: const [],
        textOverlays: const [],
        totalDuration: 4,
      );
      return _cmd(plan, ExportSettings.reels(), '/out/x.mp4');
    }

    expect(audioFilterFor(4.0), contains('atempo=2,atempo=2'));
    expect(audioFilterFor(0.25), contains('atempo=0.5,atempo=0.5'));
    expect(audioFilterFor(1.5), contains('atempo=1.5'));
    expect(audioFilterFor(1.0), isNot(contains('atempo')));
    expect(audioFilterFor(1.0), isNot(contains('setpts')));
  });

  test('identity color adjust emits no eq/colortemperature/lut3d', () {
    final plan = ExportPlan(
      videoClips: [PlannedVideoClip(clip: _clip(), hasAudio: false)],
      audioClips: const [],
      textOverlays: const [],
      totalDuration: 4,
    );
    final cmd = _cmd(plan, ExportSettings.reels(), '/out/x.mp4');
    expect(cmd, isNot(contains('eq=')));
    expect(cmd, isNot(contains('colortemperature')));
    expect(cmd, isNot(contains('lut3d')));
    // No audio inputs -> no audio map.
    expect(cmd, isNot(contains('-c:a')));
  });

  test('drawtext skipped gracefully when no font is available', () {
    final plan = ExportPlan(
      videoClips: [PlannedVideoClip(clip: _clip(), hasAudio: false)],
      audioClips: const [],
      textOverlays: [
        TextOverlay(id: 't', text: 'hi', start: 0, duration: 1),
      ],
      totalDuration: 4,
      fontPath: null,
    );
    final cmd = _cmd(plan, ExportSettings.reels(), '/out/x.mp4');
    expect(cmd, isNot(contains('drawtext')));
  });

  test('h265 preset maps to libx265', () {
    final plan = ExportPlan(
      videoClips: [PlannedVideoClip(clip: _clip(), hasAudio: false)],
      audioClips: const [],
      textOverlays: const [],
      totalDuration: 4,
    );
    const settings = ExportSettings(
      width: 1280,
      height: 720,
      fps: 60,
      bitrateMbps: 8,
      codec: ExportCodec.h265,
    );
    final cmd = _cmd(plan, settings, '/out/x.mp4');
    expect(cmd, contains('-c:v libx265'));
    expect(cmd, contains('-r 60'));
    expect(cmd, contains('scale=1280:720'));
  });
}
