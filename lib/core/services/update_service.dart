import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A release published at [UpdateService.manifestUrl].
class AppRelease {
  final String version; // e.g. 0.0.30
  final int buildNumber; // e.g. 24
  final String date;
  final String notes;
  final String apkUrl;
  final String ipaUrl;
  final bool ipaAvailable;

  const AppRelease({
    required this.version,
    required this.buildNumber,
    required this.date,
    required this.notes,
    required this.apkUrl,
    required this.ipaUrl,
    required this.ipaAvailable,
  });

  /// Reads the same `latest.json` the download page renders itself from, so the
  /// app and the website can never disagree about what the newest build is.
  factory AppRelease.fromJson(Map<String, dynamic> j, String base) {
    String abs(String? path) {
      final p = path ?? '';
      if (p.isEmpty) return '';
      return p.startsWith('http') ? p : '$base/$p';
    }

    final apk = (j['apk'] as Map?)?.cast<String, dynamic>() ?? const {};
    final ipa = (j['ipa'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AppRelease(
      version: (j['version'] ?? '').toString(),
      buildNumber: int.tryParse((j['buildNumber'] ?? '').toString()) ?? 0,
      date: (j['date'] ?? '').toString(),
      notes: (j['notes'] ?? '').toString(),
      apkUrl: abs(apk['url'] as String?),
      ipaUrl: abs(ipa['url'] as String?),
      ipaAvailable: ipa['available'] == true,
    );
  }
}

/// Checks whether a newer build has been published.
///
/// Platform split is deliberate:
///  * **Android** — sideloaded APKs have no store to update them, so the app
///    points the user straight at the new APK.
///  * **iOS** — AltStore/SideStore already poll the source manifest and handle
///    updating, so the app only needs to *tell* the user one exists; offering a
///    download would be a dead end, since iOS can't install an IPA from a
///    browser.
class UpdateService {
  static const manifestUrl = 'https://lillq.me/foxlations/latest.json';
  static const sourceUrl = 'https://lillq.me/foxlations/altstore.json';
  static const siteUrl = 'https://lillq.me/foxlations';

  static const _lastSeenKey = 'update_last_seen_build';
  static const _lastCheckKey = 'update_last_check_ms';

  /// Returns the published release when it is newer than what's running,
  /// otherwise null. Never throws — a failed check must not disrupt startup.
  static Future<AppRelease?> check({bool force = false}) async {
    try {
      if (!force && !await _dueForCheck()) return null;

      final res = await http
          .get(Uri.parse('$manifestUrl?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final release = AppRelease.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
        siteUrl,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);

      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;

      // Compare build numbers, not version strings: the build number is a
      // single monotonically increasing integer, so there's no dotted-version
      // parsing to get wrong.
      if (release.buildNumber <= current) return null;

      // On iOS a release is only actionable once its IPA is actually published;
      // announcing one AltStore can't fetch would just be noise.
      if (Platform.isIOS && !release.ipaAvailable) return null;

      return release;
    } catch (e) {
      debugPrint('[Update] check failed: $e');
      return null;
    }
  }

  /// Throttles background checks to once every 12 hours.
  static Future<bool> _dueForCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastCheckKey) ?? 0;
    const twelveHours = 12 * 60 * 60 * 1000;
    return DateTime.now().millisecondsSinceEpoch - last > twelveHours;
  }

  /// True when this build has already been shown to the user and dismissed, so
  /// the prompt doesn't reappear on every launch.
  static Future<bool> alreadyDismissed(int buildNumber) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_lastSeenKey) ?? 0) >= buildNumber;
  }

  static Future<void> dismiss(int buildNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSeenKey, buildNumber);
  }
}
