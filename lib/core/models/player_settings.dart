import 'package:shared_preferences/shared_preferences.dart';

/// User-configurable video-player options, persisted in SharedPreferences and read
/// by the player to build media_kit's controls theme. All have sensible defaults so
/// the player works before the user ever opens the Player settings page.
class PlayerSettings {
  /// Seconds skipped when double-tapping the right / left side of the screen.
  final int seekForwardSeconds; // default 10
  final int seekBackwardSeconds; // default 10

  /// Hold anywhere to temporarily play faster; the multiplier applied while held.
  final bool longPressSpeedUp; // default true
  final double speedFactor; // default 2.0

  /// Vertical-swipe gestures: volume on the right half, brightness on the left.
  final bool volumeGesture; // default true
  final bool brightnessGesture; // default true

  /// Start the next episode automatically when one finishes.
  final bool autoplayNext; // default true

  /// Playback speed a freshly-opened episode starts at.
  final double defaultSpeed; // default 1.0

  /// Skip source-provided intro/outro ranges automatically (vs. showing a button).
  final bool autoSkipIntro; // default false

  const PlayerSettings({
    this.seekForwardSeconds = 10,
    this.seekBackwardSeconds = 10,
    this.longPressSpeedUp = true,
    this.speedFactor = 2.0,
    this.volumeGesture = true,
    this.brightnessGesture = true,
    this.autoplayNext = true,
    this.defaultSpeed = 1.0,
    this.autoSkipIntro = false,
  });

  static const kSeekForward = 'player_seek_forward';
  static const kSeekBackward = 'player_seek_backward';
  static const kLongPressSpeedUp = 'player_longpress_speedup';
  static const kSpeedFactor = 'player_speed_factor';
  static const kVolumeGesture = 'player_volume_gesture';
  static const kBrightnessGesture = 'player_brightness_gesture';
  static const kAutoplayNext = 'player_autoplay_next';
  static const kDefaultSpeed = 'player_default_speed';
  static const kAutoSkipIntro = 'player_auto_skip_intro';

  static Future<PlayerSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return PlayerSettings(
      seekForwardSeconds: p.getInt(kSeekForward) ?? 10,
      seekBackwardSeconds: p.getInt(kSeekBackward) ?? 10,
      longPressSpeedUp: p.getBool(kLongPressSpeedUp) ?? true,
      speedFactor: p.getDouble(kSpeedFactor) ?? 2.0,
      volumeGesture: p.getBool(kVolumeGesture) ?? true,
      brightnessGesture: p.getBool(kBrightnessGesture) ?? true,
      autoplayNext: p.getBool(kAutoplayNext) ?? true,
      defaultSpeed: p.getDouble(kDefaultSpeed) ?? 1.0,
      autoSkipIntro: p.getBool(kAutoSkipIntro) ?? false,
    );
  }

  static Future<void> setInt(String key, int v) async =>
      (await SharedPreferences.getInstance()).setInt(key, v);
  static Future<void> setBool(String key, bool v) async =>
      (await SharedPreferences.getInstance()).setBool(key, v);
  static Future<void> setDouble(String key, double v) async =>
      (await SharedPreferences.getInstance()).setDouble(key, v);
}
