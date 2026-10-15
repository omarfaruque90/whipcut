import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub API endpoint for the newest Whipcut release.
const String kWhipcutReleasesApi =
    'https://api.github.com/repos/omarfaruque90/whipcut/releases/latest';

/// Network timeout for the version check (spec: 10s, fail silently).
const Duration kUpdateCheckTimeout = Duration(seconds: 10);

/// Native channel for app-version lookup and APK install intents.
const MethodChannel _updateChannel = MethodChannel('whipcut/update');

/// A GitHub release that carries an installable APK asset.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.notes,
    required this.apkUrl,
  });

  /// Raw tag, e.g. "v0.1".
  final String tagName;

  /// Normalized version, e.g. "0.1".
  final String version;

  /// Release notes (body), may be empty.
  final String notes;

  /// `browser_download_url` of the .apk asset.
  final String apkUrl;
}

/// Byte source for an APK download: the response stream plus the
/// advertised content length (-1 when unknown).
class DownloadSource {
  const DownloadSource({required this.stream, required this.totalBytes});

  final Stream<List<int>> stream;
  final int totalBytes;
}

/// Result of a version check.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.release,
    required this.available,
  });

  /// Installed app version, e.g. "1.0.0".
  final String currentVersion;

  /// Latest release, or null when the check failed (offline, timeout…).
  final ReleaseInfo? release;

  /// True when [release] is newer than [currentVersion].
  final bool available;
}

/// In-app update checker (Khorcha-style).
///
/// Network goes through `dart:io` [HttpClient] — no extra packages needed.
/// The installed version and the APK install intent are bridged over the
/// `whipcut/update` [MethodChannel] (see `MainActivity.kt`).
class UpdateService {
  /// [versionReader] is injectable for tests; defaults to the native channel.
  UpdateService({Future<String> Function()? versionReader})
      : _versionReader = versionReader ?? _readVersionNative;

  final Future<String> Function() _versionReader;

  // ------------------------------------------------------------------
  // Version parsing / comparison (pure — fully unit-tested).
  // ------------------------------------------------------------------

  /// Strips a leading "v", surrounding whitespace, pre-release ("-…") and
  /// build metadata ("+…") suffixes. "v0.1" → "0.1", "1.0.0+5" → "1.0.0".
  static String normalizeVersion(String raw) {
    var v = raw.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final plus = v.indexOf('+');
    if (plus >= 0) v = v.substring(0, plus);
    final dash = v.indexOf('-');
    if (dash >= 0) v = v.substring(0, dash);
    return v;
  }

  static List<int> _segments(String version) => normalizeVersion(version)
      .split('.')
      .map((s) => int.tryParse(s.trim()) ?? 0)
      .toList();

  /// Numeric segment-by-segment comparison. Returns >0 if [a] > [b],
  /// <0 if [a] < [b], 0 when equal. Missing segments count as 0, so
  /// "1.0" == "1.0.0" and "0.2" > "0.1.9".
  static int compareVersions(String a, String b) {
    final sa = _segments(a);
    final sb = _segments(b);
    final len = sa.length > sb.length ? sa.length : sb.length;
    for (var i = 0; i < len; i++) {
      final x = i < sa.length ? sa[i] : 0;
      final y = i < sb.length ? sb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// True when [latestVersion] is strictly newer than [currentVersion].
  static bool isUpdateAvailable(String currentVersion, String latestVersion) =>
      compareVersions(latestVersion, currentVersion) > 0;

  // ------------------------------------------------------------------
  // Release metadata.
  // ------------------------------------------------------------------

  /// Parses a GitHub release JSON object. Returns null when there is no
  /// usable `.apk` asset (or no tag).
  static ReleaseInfo? parseReleaseJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String?;
    if (tag == null || tag.trim().isEmpty) return null;
    String? apkUrl;
    final assets = json['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          final url = asset['browser_download_url'] as String?;
          if (name.endsWith('.apk') && url != null && url.isNotEmpty) {
            apkUrl = url;
            break;
          }
        }
      }
    }
    if (apkUrl == null) return null;
    return ReleaseInfo(
      tagName: tag,
      version: normalizeVersion(tag),
      notes: (json['body'] as String? ?? '').trim(),
      apkUrl: apkUrl,
    );
  }

  /// Fetches the latest release. Any failure (offline, timeout, bad JSON,
  /// no APK asset) returns null — the caller silently skips the prompt.
  ///
  /// [fetchBody] overrides the network call (used by tests).
  Future<ReleaseInfo?> fetchLatestRelease({
    Future<String> Function(Uri uri)? fetchBody,
  }) async {
    try {
      final uri = Uri.parse(kWhipcutReleasesApi);
      final String body;
      if (fetchBody != null) {
        body = await fetchBody(uri).timeout(kUpdateCheckTimeout);
      } else {
        body = await _httpGet(uri).timeout(kUpdateCheckTimeout);
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      return parseReleaseJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<String> _httpGet(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Whipcut-Android');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub API returned ${response.statusCode}');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  // ------------------------------------------------------------------
  // Installed version + install.
  // ------------------------------------------------------------------

  static Future<String> _readVersionNative() async {
    try {
      final v = await _updateChannel.invokeMethod<String>('getAppVersion');
      return (v == null || v.trim().isEmpty) ? '0.0.0' : v.trim();
    } catch (_) {
      return '0.0.0';
    }
  }

  /// Installed app version, e.g. "1.0.0".
  Future<String> getInstalledVersion() => _versionReader();

  /// Full check: installed version vs latest release.
  Future<UpdateCheckResult> checkNow() async {
    final current = await getInstalledVersion();
    final release = await fetchLatestRelease();
    if (release == null) {
      return UpdateCheckResult(
          currentVersion: current, release: null, available: false);
    }
    return UpdateCheckResult(
      currentVersion: current,
      release: release,
      available: isUpdateAvailable(current, release.version),
    );
  }

  /// Downloads the release APK to the temp dir. Throws on failure.
  ///
  /// [saveDir] overrides the temp dir and [fetchStream] overrides the
  /// network call (both used by tests).
  Future<File> downloadApk(
    String url, {
    Directory? saveDir,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    Future<DownloadSource> Function(Uri uri)? fetchStream,
  }) async {
    final dir = saveDir ?? await getTemporaryDirectory();
    final file = File('${dir.path}/whipcut-update.apk');
    if (await file.exists()) await file.delete();

    final DownloadSource source;
    HttpClient? client;
    try {
      if (fetchStream != null) {
        source = await fetchStream(Uri.parse(url));
      } else {
        client = HttpClient();
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set(HttpHeaders.userAgentHeader, 'Whipcut-Android');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('APK download returned ${response.statusCode}');
        }
        source = DownloadSource(
            stream: response, totalBytes: response.contentLength);
      }

      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in source.stream) {
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(received, source.totalBytes);
        }
      } finally {
        await sink.close();
      }
      return file;
    } finally {
      client?.close(force: true);
    }
  }

  /// Fires the Android package-installer intent for [apkFile].
  Future<void> installApk(File apkFile) =>
      _updateChannel.invokeMethod('installApk', {'path': apkFile.path});
}
