import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/player_settings.dart';

/// Video-player options — feeds media_kit's controls theme (double-tap seek
/// distances, gestures, long-press speed, autoplay, default speed).
class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  State<PlayerSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  PlayerSettings _s = const PlayerSettings();

  @override
  void initState() {
    super.initState();
    PlayerSettings.load().then((v) {
      if (mounted) setState(() => _s = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Player',
            style: GoogleFonts.manrope(
                fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
      ),
      body: SafeArea(
        child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _header(cs, 'DOUBLE-TAP TO SEEK'),
          _pick(cs, 'Skip forward', '${_s.seekForwardSeconds}s', () async {
            final v = await _pickSeconds(_s.seekForwardSeconds);
            if (v != null) {
              await PlayerSettings.setInt(PlayerSettings.kSeekForward, v);
              setState(() => _s = _copy(seekForwardSeconds: v));
            }
          }),
          _pick(cs, 'Skip backward', '${_s.seekBackwardSeconds}s', () async {
            final v = await _pickSeconds(_s.seekBackwardSeconds);
            if (v != null) {
              await PlayerSettings.setInt(PlayerSettings.kSeekBackward, v);
              setState(() => _s = _copy(seekBackwardSeconds: v));
            }
          }),
          _header(cs, 'GESTURES'),
          _toggle(cs, 'Hold to speed up',
              'Press and hold anywhere to play at ${_s.speedFactor}x', _s.longPressSpeedUp,
              (v) async {
            await PlayerSettings.setBool(PlayerSettings.kLongPressSpeedUp, v);
            setState(() => _s = _copy(longPressSpeedUp: v));
          }),
          _pick(cs, 'Hold speed', '${_s.speedFactor}x', () async {
            final v = await _pickSpeed(_s.speedFactor, const [1.25, 1.5, 2.0, 2.5, 3.0]);
            if (v != null) {
              await PlayerSettings.setDouble(PlayerSettings.kSpeedFactor, v);
              setState(() => _s = _copy(speedFactor: v));
            }
          }),
          _toggle(cs, 'Volume swipe', 'Slide up/down on the right half to adjust volume',
              _s.volumeGesture, (v) async {
            await PlayerSettings.setBool(PlayerSettings.kVolumeGesture, v);
            setState(() => _s = _copy(volumeGesture: v));
          }),
          _toggle(cs, 'Brightness swipe',
              'Slide up/down on the left half to adjust brightness', _s.brightnessGesture,
              (v) async {
            await PlayerSettings.setBool(PlayerSettings.kBrightnessGesture, v);
            setState(() => _s = _copy(brightnessGesture: v));
          }),
          _header(cs, 'PLAYBACK'),
          _pick(cs, 'Default speed', '${_s.defaultSpeed}x', () async {
            final v = await _pickSpeed(
                _s.defaultSpeed, const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]);
            if (v != null) {
              await PlayerSettings.setDouble(PlayerSettings.kDefaultSpeed, v);
              setState(() => _s = _copy(defaultSpeed: v));
            }
          }),
          _toggle(cs, 'Autoplay next episode',
              'Start the next episode automatically when one ends', _s.autoplayNext,
              (v) async {
            await PlayerSettings.setBool(PlayerSettings.kAutoplayNext, v);
            setState(() => _s = _copy(autoplayNext: v));
          }),
          _toggle(cs, 'Auto-skip intro/outro',
              'Skip source-marked openings/endings without tapping', _s.autoSkipIntro,
              (v) async {
            await PlayerSettings.setBool(PlayerSettings.kAutoSkipIntro, v);
            setState(() => _s = _copy(autoSkipIntro: v));
          }),
        ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(text,
            style: GoogleFonts.manrope(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: cs.primary)),
      );

  Widget _toggle(ColorScheme cs, String title, String subtitle, bool value,
          ValueChanged<bool> onChanged) =>
      SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: cs.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(title,
            style: GoogleFonts.manrope(
                fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
        subtitle: Text(subtitle,
            style: GoogleFonts.manrope(fontSize: 12.5, color: cs.outline)),
      );

  Widget _pick(ColorScheme cs, String title, String value, VoidCallback onTap) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        onTap: onTap,
        title: Text(title,
            style: GoogleFonts.manrope(
                fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
        trailing: Text(value,
            style: GoogleFonts.manrope(
                fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary)),
      );

  Future<int?> _pickSeconds(int current) => showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Skip amount',
              style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
          children: [
            for (final s in const [5, 10, 15, 30, 60, 90])
              _dialogRow(ctx, '${s}s', s, s == current),
          ],
        ),
      );

  Future<double?> _pickSpeed(double current, List<double> options) => showDialog<double>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Speed',
              style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
          children: [
            for (final s in options) _dialogRow(ctx, '${s}x', s, s == current),
          ],
        ),
      );

  Widget _dialogRow<T>(BuildContext ctx, String label, T value, bool selected) {
    final cs = Theme.of(ctx).colorScheme;
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, value),
      child: Row(
        children: [
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              size: 18, color: selected ? cs.primary : cs.outline),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface)),
        ],
      ),
    );
  }

  PlayerSettings _copy({
    int? seekForwardSeconds,
    int? seekBackwardSeconds,
    bool? longPressSpeedUp,
    double? speedFactor,
    bool? volumeGesture,
    bool? brightnessGesture,
    bool? autoplayNext,
    double? defaultSpeed,
    bool? autoSkipIntro,
  }) =>
      PlayerSettings(
        seekForwardSeconds: seekForwardSeconds ?? _s.seekForwardSeconds,
        seekBackwardSeconds: seekBackwardSeconds ?? _s.seekBackwardSeconds,
        longPressSpeedUp: longPressSpeedUp ?? _s.longPressSpeedUp,
        speedFactor: speedFactor ?? _s.speedFactor,
        volumeGesture: volumeGesture ?? _s.volumeGesture,
        brightnessGesture: brightnessGesture ?? _s.brightnessGesture,
        autoplayNext: autoplayNext ?? _s.autoplayNext,
        defaultSpeed: defaultSpeed ?? _s.defaultSpeed,
        autoSkipIntro: autoSkipIntro ?? _s.autoSkipIntro,
      );
}
