import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/update_prompt.dart';
import 'vault_settings_page.dart';

class AboutSettingsPage extends StatefulWidget {
  const AboutSettingsPage({super.key});

  @override
  State<AboutSettingsPage> createState() => _AboutSettingsPageState();
}

class _AboutSettingsPageState extends State<AboutSettingsPage> {
  // Update these once a public repo exists.
  static const _sourceCodeUrl = 'https://github.com/ghotato/foxlations';
  static const _bugReportUrl = 'https://github.com/ghotato/foxlations/issues';

  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  String get _versionLabel {
    if (_info == null) return '';
    return 'Version ${_info!.version} (Build ${_info!.buildNumber})';
  }

  String get _version => _info?.version ?? '';

  // Secret vault opener: tap the Foxlations logo 9× (moved here from Appearance
  // settings). Fast consecutive taps only, so it isn't triggered by accident.
  int _logoTapCount = 0;
  DateTime _lastLogoTap = DateTime(2000);

  void _onLogoTap(BuildContext context) {
    final now = DateTime.now();
    _logoTapCount =
        now.difference(_lastLogoTap).inMilliseconds < 600 ? _logoTapCount + 1 : 1;
    _lastLogoTap = now;

    if (_logoTapCount >= 7 && _logoTapCount < 9) {
      final remaining = 9 - _logoTapCount;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(
              '$remaining more tap${remaining == 1 ? '' : 's'} to open vault settings'),
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
        ));
    }
    if (_logoTapCount >= 9) {
      _logoTapCount = 0;
      ScaffoldMessenger.of(context).clearSnackBars();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VaultSettingsPage()),
      );
    }
  }

  Future<void> _copyLink(BuildContext context, String url, String label) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      AppTheme.showSnackBar(context, '$label link copied to clipboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: cs.onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'About',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.only(
            top: 12, bottom: 12 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          // App hero card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onLogoTap(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/images/foxlations.png',
                      width: 72,
                      height: 72,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Foxlations',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _versionLabel,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: cs.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: 'App'),
          _ActionTile(
            icon: Icons.new_releases_rounded,
            iconColor: cs.primary,
            iconBg: isDark
                ? const Color(0xFF3D1A10)
                : const Color(0xFFFFEDE8),
            title: "What's New",
            subtitle: 'Changelog and release notes',
            onTap: () => _showChangelog(context),
          ),
          _ActionTile(
            icon: Icons.system_update_rounded,
            iconColor: AppTheme.success,
            iconBg: isDark
                ? const Color(0xFF0D2E1E)
                : const Color(0xFFE6F7EF),
            title: 'Check for Updates',
            subtitle: 'See if a newer build has been released',
            // Previously this always claimed "Already on the latest version"
            // without checking anything. It now reads the same latest.json the
            // download page uses, so the app and site can't disagree.
            onTap: () => UpdatePrompt.maybeShow(context, force: true),
          ),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Legal'),
          _ActionTile(
            icon: Icons.description_rounded,
            iconColor: AppTheme.secondary,
            iconBg: isDark
                ? const Color(0xFF1A1640)
                : const Color(0xFFEEEDFF),
            title: 'Licenses',
            subtitle: 'Open source licenses',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Foxlations',
              applicationVersion: _version,
            ),
          ),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Links'),
          _ActionTile(
            icon: Icons.code_rounded,
            iconColor: cs.outline,
            iconBg: cs.surfaceContainerHighest,
            title: 'Source Code',
            subtitle: 'Tap to copy GitHub URL',
            onTap: () => _copyLink(context, _sourceCodeUrl, 'Source code'),
          ),
          _ActionTile(
            icon: Icons.bug_report_rounded,
            iconColor: AppTheme.error,
            iconBg: isDark
                ? const Color(0xFF2E0A0A)
                : const Color(0xFFFFEEEE),
            title: 'Report a Bug',
            subtitle: 'Tap to copy issue tracker URL',
            onTap: () => _copyLink(context, _bugReportUrl, 'Bug report'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showChangelog(BuildContext context) {
    final versionTitle = _version.isNotEmpty ? "What's New in v$_version" : "What's New";
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        title: Text(
          versionTitle,
          style: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55),
            child: SingleChildScrollView(
              child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChangelogItem('Foxlations 1.0.0 — the first official release. The '
                'headline: it now runs on-device extensions for manga, manhwa, '
                'manhua, light novels and anime, right on your device, and video '
                'picks up where you left off — reopen an episode to continue or '
                'start over. Everything else below.'),
            _ChangelogItem('Anime is here. Add an anime source and stream episodes '
                'in the built-in player. The app converts the extension on your '
                'device and finds the video for you.'),
            _ChangelogItem('Light novels remember your place. Continue now returns you '
                'to the exact spot you scrolled to — novels have no pages, so it saves '
                'your scroll position, not a page number.'),
            _ChangelogItem('Volume-button reading, done right. Tap volume to turn a page '
                '(left-to-right) or scroll a screen (webtoon); HOLD to scroll slowly and '
                'fluidly like dragging, at a speed you can set in Reader settings. Now on '
                'iOS too (experimental — it warns you first, since it pins media volume '
                'to 50% while reading). The video player keeps normal volume control.'),
            _ChangelogItem('Video resume that sticks (Android). Continuing an episode now '
                're-seeks until it actually holds at your spot — Android was accepting the '
                'seek then quietly restarting from 0.'),
            _ChangelogItem('Player seek bar no longer clipped. In landscape the progress '
                'bar and time were jammed against the bottom edge; they now sit above '
                'the system/gesture area.'),
            _ChangelogItem('Resume actually resumes. Picking "Continue" on an episode '
                'now reliably jumps to where you left off — the player waits for the '
                'video to load before seeking, instead of silently starting over.'),
            _ChangelogItem('Player menus fit the screen. The subtitle, audio, quality '
                'and speed pickers now scroll and cap their height, so options like '
                '"Subtitle delay" no longer get cut off the bottom in landscape.'),
            _ChangelogItem('Nothing hides under the navigation bar (Android). Settings '
                'and every other screen now pad themselves by your phone\'s actual '
                'system-bar size — gesture pill, 3-button bar, or none — so the last '
                'row never sits under the bottom bar, on any device.'),
            _ChangelogItem('The per-source "Update" button works. Updating one source '
                'from the list now confirms it updated (or tells you why it didn\'t) '
                'instead of quietly doing nothing; "Update all" is unchanged.'),
            _ChangelogItem('No more crashing when you reopen the app (iOS). Returning '
                'to Foxlations from the background after using a source no longer '
                'closes it — the extension engine now hands signal handling back to '
                'the app between jobs. Player and video-load problems also show up in '
                'the in-app log now (More → Debug logs).'),
            _ChangelogItem('Anime sound and details, fixed. Episodes that stream '
                'their audio as a separate track now play with sound, and sources '
                'that report a full web address for a title (instead of a short path) '
                'load their details and episodes again instead of failing.'),
            _ChangelogItem('Kotlin extensions run on-device. Alongside JavaScript '
                'and Dart, Foxlations now runs Kotlin manga, light-novel and anime '
                'extensions directly — so most existing source repos just work, no '
                'computer or server needed.'),
            _ChangelogItem('Gets past Cloudflare. Protected sources clear the check '
                'with a quick in-app verify step, and the app remembers it.'),
            _ChangelogItem('Big repos, sorted properly. Sources from large repos '
                'now show their real language and content rating — filter '
                'by language, and safe-for-work sources appear without turning on '
                '18+ content.'),
            _ChangelogItem('Reading & watching, fixed up. Light-novel chapters open '
                'and read, comic pages (and their images) load on sources that key '
                'off internal IDs, added repos come back instantly on relaunch, and '
                'anime now remembers where you stopped — reopen an episode to '
                'continue or start over.'),
            _ChangelogItem('Sources survive updates. Installed extensions no longer '
                '"fail to load" after an app re-sign or reinstall — their files are '
                'found again automatically, so you don\'t have to re-add them.'),
            _ChangelogItem('Clearer and quicker. Cloudflare-protected sources show a '
                '"Bypassing Cloudflare…" notice and whether it succeeded, and the '
                'extension engine warms up in the background when you open Browse, so '
                'the first source you open loads sooner.'),
            _ChangelogItem('More light novels read cleanly. API-based novel sources '
                '(like Novel Archive) now show the chapter text instead of a stray '
                'link.'),
            _ChangelogItem('No more closing on return. Coming back to the app after '
                'it sat in the background no longer crashes, and unexpected errors '
                'now show up in the in-app log (More → Debug logs).'),
            _ChangelogItem('Plus everything from the recent updates: in-reader AI '
                'translation over the speech bubbles, the Manga / Anime / Light '
                'Novel library filters, swipe between categories, and the unread '
                'badge that counts down as you read.'),
          ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangelogItem extends StatelessWidget {
  final String text;
  const _ChangelogItem(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: cs.onSurface,
              ),
            ),
          ),
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
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: cs.outline,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: cs.outline, size: 20),
          ],
        ),
      ),
    );
  }
}
