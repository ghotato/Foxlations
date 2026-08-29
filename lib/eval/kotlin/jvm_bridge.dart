import 'dart:convert';

import 'package:flutter/services.dart';

/// Dart side of the embedded-JVM MethodChannel (M5.1).
///
/// The native `foxlations/jvm` channel is only registered in the JVM build
/// (`-DFOXLATIONS_JVM`); in a normal build [probe] returns a "not available"
/// message instead of throwing, so callers stay simple. Later milestones add the
/// real source methods (getPopular/getDetail/getPageList/…) behind
/// `KotlinExtensionService`; for now this is just the boot + fetch self-test.
class FoxJvm {
  static const MethodChannel _channel = MethodChannel('foxlations/jvm');

  /// Boots the embedded Zero VM (once) and runs the Suwayomi-hosted MangaDex
  /// fetch self-test, returning its human-readable report. Never throws.
  static Future<String> probe() async {
    try {
      final result = await _channel.invokeMethod<String>('probe');
      return result ?? '(no report)';
    } on MissingPluginException {
      return 'JVM channel not available — this build has no embedded JVM.';
    } on PlatformException catch (e) {
      return 'JVM probe error: ${e.message ?? e.code}';
    }
  }

  /// Boots the embedded JVM ahead of time (best-effort, never throws) so the first
  /// real source call doesn't pay the one-time bootstrap cost. The app calls this in
  /// the background when Browse opens and Kotlin sources are installed.
  static Future<void> warmup() async {
    try {
      await _channel.invokeMethod<String>('invoke', jsonEncode({'method': 'warmup'}));
    } catch (_) {}
  }

  /// M5.2: send a JSON [request] ({method, jar, lang?, page?, query?, url?}) to
  /// `SourceRunner.invoke` on the JVM and return the decoded JSON response
  /// (a Map for MPages/MManga, a List for getPageList). Throws on an error
  /// response or a missing channel so `KotlinExtensionService` surfaces it.
  static Future<dynamic> invoke(Map<String, dynamic> request) async {
    final String resp;
    try {
      resp = await _channel.invokeMethod<String>('invoke', jsonEncode(request)) ??
          '{"error":"null response"}';
    } on MissingPluginException {
      throw Exception('JVM channel not available — this build has no embedded JVM.');
    } on PlatformException catch (e) {
      throw Exception('JVM invoke error: ${e.message ?? e.code}');
    }
    final decoded = jsonDecode(resp);
    if (decoded is Map && decoded['error'] != null) {
      throw Exception('Kotlin source error: ${decoded['error']}');
    }
    return decoded;
  }
}
