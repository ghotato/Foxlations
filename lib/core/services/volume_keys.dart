import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

import 'app_logger.dart';

/// Hardware volume-button page navigation.
///
/// Android: native key capture (MainActivity.dispatchKeyEvent) swallows the buttons and
/// reports {dir, phase} — 'down' on press, 'up' on release — so the reader can tell a tap
/// from a hold. System volume is never touched.
///
/// iOS: there is NO volume-button event API, so this observes the system volume, hides the
/// HUD, and infers a press from the delta, resetting to a midpoint each time. It's
/// EXPERIMENTAL — while active the media volume is pinned to ~50% (the reader warns the
/// user before enabling). iOS can't detect hold/release, so every press is a tap.
class VolumeKeys {
  static const _channel = MethodChannel('foxlations/volume_keys');

  static const double _mid = 0.5;
  static bool _iosActive = false;
  static bool _iosResetting = false;
  static double _iosLast = _mid;

  /// Begin capturing. [onKey] receives (dir: 'up'|'down', phase: 'down'|'up').
  static Future<void> enable(void Function(String dir, String phase) onKey) async {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onKey' && call.arguments is Map) {
          final m = Map<String, dynamic>.from(call.arguments as Map);
          final dir = m['dir'] as String? ?? '';
          final phase = m['phase'] as String? ?? 'down';
          if (dir.isNotEmpty) onKey(dir, phase);
        }
        return null;
      });
      try {
        await _channel.invokeMethod('setCapture', true);
        logger.info('Volume-key capture enabled (Android)',
            category: LogCategory.general);
      } catch (e) {
        logger.error('Volume-key capture failed: $e',
            category: LogCategory.general);
      }
    } else if (Platform.isIOS) {
      await _enableIos(onKey);
    }
  }

  static Future<void> _enableIos(
      void Function(String dir, String phase) onKey) async {
    try {
      await FlutterVolumeController.updateShowSystemUI(false);
      _iosLast = (await FlutterVolumeController.getVolume()) ?? _mid;
      // Park at the midpoint so both up and down have headroom (a press at 0/1 is
      // otherwise missed).
      _iosResetting = true;
      await FlutterVolumeController.setVolume(_mid);
      _iosLast = _mid;
      _iosResetting = false;
      _iosActive = true;
      FlutterVolumeController.addListener((v) {
        if (_iosResetting || !_iosActive) return;
        final dir = v > _iosLast ? 'up' : 'down';
        // iOS can't distinguish hold from tap — deliver a tap (down then up).
        onKey(dir, 'down');
        onKey(dir, 'up');
        // Reset to the midpoint for the next press (guard so this doesn't re-trigger).
        _iosResetting = true;
        FlutterVolumeController.setVolume(_mid).then((_) {
          _iosLast = _mid;
          _iosResetting = false;
        });
      }, emitOnStart: false);
      logger.info('Volume-key capture enabled (iOS, experimental)',
          category: LogCategory.general);
    } catch (e) {
      logger.error('iOS volume capture failed: $e', category: LogCategory.general);
    }
  }

  /// Stop capturing; the buttons return to controlling system volume.
  static Future<void> disable() async {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(null);
      try {
        await _channel.invokeMethod('setCapture', false);
      } catch (_) {}
    } else if (Platform.isIOS) {
      _iosActive = false;
      FlutterVolumeController.removeListener();
      try {
        await FlutterVolumeController.updateShowSystemUI(true);
      } catch (_) {}
    }
  }
}
