import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../theme/app_theme.dart';

/// Security preference keys. Toggling persists the choice — runtime
/// enforcement (app lock screen, biometric prompt, FLAG_SECURE) requires
/// platform plugins (local_auth / window flags) which are not yet wired up.
class SecurityPrefs {
  static const appLock = 'sec_app_lock';
  static const biometrics = 'sec_biometrics';
  static const secureScreen = 'sec_secure_screen';
  static const hideNotificationContent = 'sec_hide_notif_content';
}

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});
  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  bool _appLock = false;
  bool _biometrics = false;
  bool _secureScreen = false;
  bool _hideNotificationContent = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _appLock = p.getBool(SecurityPrefs.appLock) ?? false;
      _biometrics = p.getBool(SecurityPrefs.biometrics) ?? false;
      _secureScreen = p.getBool(SecurityPrefs.secureScreen) ?? false;
      _hideNotificationContent =
          p.getBool(SecurityPrefs.hideNotificationContent) ?? false;
    });
  }

  Future<void> _setBool(String key, bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: Text('Security & Privacy',
            style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(title: 'App Lock'),
          _SwitchTile(icon: Icons.lock_rounded, iconColor: const Color(0xFF5865F2),
              title: 'App Lock', subtitle: 'Require authentication to open app',
              value: _appLock, onChanged: (v) {
                setState(() => _appLock = v);
                _setBool(SecurityPrefs.appLock, v);
              }),
          _SwitchTile(icon: Icons.fingerprint_rounded, iconColor: const Color(0xFF5865F2),
              title: 'Biometrics', subtitle: 'Use fingerprint or face to unlock',
              value: _biometrics, onChanged: (v) {
                setState(() => _biometrics = v);
                _setBool(SecurityPrefs.biometrics, v);
              }),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Privacy'),
          _SwitchTile(icon: Icons.visibility_off_rounded, iconColor: AppTheme.warning,
              title: 'Secure Screen', subtitle: 'Hide app content in recent apps',
              value: _secureScreen, onChanged: (v) {
                setState(() => _secureScreen = v);
                _setBool(SecurityPrefs.secureScreen, v);
              }),
          _SwitchTile(icon: Icons.notifications_off_rounded, iconColor: AppTheme.warning,
              title: 'Hide Notification Content', subtitle: 'Show generic notification text',
              value: _hideNotificationContent, onChanged: (v) {
                setState(() => _hideNotificationContent = v);
                _setBool(SecurityPrefs.hideNotificationContent, v);
              }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(title.toUpperCase(),
          style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: cs.primary)),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title; final String subtitle;
  final bool value; final ValueChanged<bool> onChanged;
  const _SwitchTile({required this.icon, required this.iconColor, required this.title,
      required this.subtitle, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: cs.outlineVariant)),
      child: Row(children: [
        Container(width: 36, height: 36,
            decoration: BoxDecoration(color: iconColor.withAlpha(25), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          Text(subtitle, style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
        ])),
        Switch(value: value, onChanged: onChanged, activeThumbColor: cs.onPrimary, activeTrackColor: cs.primary),
      ]),
    );
  }
}
