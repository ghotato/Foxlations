import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../theme/app_theme.dart';

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
        padding: const EdgeInsets.symmetric(vertical: 12),
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/foxlations.png',
                    width: 72,
                    height: 72,
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
            subtitle: 'You are on the latest version',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Already on the latest version',
                    style: GoogleFonts.manrope(fontSize: 13),
                  ),
                  backgroundColor: cs.surfaceContainerHighest,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                ),
              );
            },
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
            _ChangelogItem('Installing a source from a repo no longer marks '
                'every other source as installed — repo entries that share no '
                'ID are now told apart, and extensions that bundle several '
                'sources let you install each one separately'),
            _ChangelogItem('Library: new Filter / Sort / Display sheet — filter '
                'by unread, completed, downloaded or source; sort by title, '
                'last read, unread count, chapters or date added; switch '
                'between grid and list, set items per row, and toggle badges'),
            _ChangelogItem('Library: new menu for Category Update, Global '
                'Update, an updates summary, multi-select, and opening a '
                'random entry'),
            _ChangelogItem('Installed sources now have a Settings button that '
                'opens the options that source provides (things like hiding '
                'premium chapters)'),
            _ChangelogItem('The Filter button on the extensions list works now '
                '— it opens a language picker instead of doing nothing'),
            _ChangelogItem('Importing a Tachiyomi/Mihon/Tachimanga backup now '
                'works — Tachimanga\'s .tmb files are recognised, and a backup '
                'that can\'t be read tells you what\'s wrong instead of failing '
                'with "RangeError"'),
            _ChangelogItem('iOS: the text in the extensions search bar is '
                'vertically centered again'),
            _ChangelogItem('iPhone/iPad support — JavaScript sources now load '
                'correctly on iOS (they previously failed with a type error on '
                'every search and browse), and searching many sources at once no '
                'longer hangs or mixes up results between them'),
            _ChangelogItem('iOS: sites served over plain http now load, video '
                'audio is no longer silenced by the Ring/Silent switch or cut '
                'off when you leave the app, and .cbz/.cbr files can be picked '
                'again when importing'),
            _ChangelogItem('iOS: Japanese, Korean and Chinese text recognition '
                'now works for AI translation — before, those pages were quietly '
                'scanned as if they were English and produced nonsense'),
            _ChangelogItem('iOS: your imported local manga and RepoForge sources '
                'no longer disappear after the app is reinstalled or re-signed'),
            _ChangelogItem('iOS: backups and downloads are now reachable from the '
                'Files app under On My iPhone › Foxlations'),
            _ChangelogItem('Reader uses far less memory — covers are decoded at '
                'the size they\'re shown and the page cache is capped by actual '
                'memory used, which stops the app being killed mid-chapter'),
            _ChangelogItem('App icon now shows the Foxlations fox on iOS instead '
                'of the default Flutter logo'),
            _ChangelogItem('Sources added from a repo now detect manga / anime / '
                'light novel correctly (reads Mangayomi-style itemType) and '
                'auto-imports a repo\'s anime and novel indexes, not just manga'),
            _ChangelogItem('Cloudflare-protected sources now work in your library '
                'and search — the app solves the check automatically, or pops a '
                'quick "verify you are human" screen if needed, then remembers it'),
            _ChangelogItem('Backup & Restore (Settings › System) — native '
                'backups, Tachiyomi/Mihon .tachibk import & export, automatic '
                'scheduled backups, and a list of your backups'),
            _ChangelogItem('Manga details no longer show raw HTML in the '
                'description; What\'s New scrolls when long; search bar text '
                'sits centered'),
            _ChangelogItem('Global search fixed — it now shows results that '
                'actually match your query instead of a source\'s popular list, '
                'and covers line up with their titles'),
            _ChangelogItem('Tracking is live — connect AniList, MyAnimeList, or '
                'Kitsu, link a manga from its Tracking button, and your chapter '
                'progress syncs automatically as you read'),
            _ChangelogItem('Custom/unknown sites now fill in the details page — '
                'title, cover, description, status, genres via OpenGraph + smart '
                'fallbacks (was blank before on bespoke sites)'),
            _ChangelogItem('RepoForge has its own home now (Settings › RepoForge): '
                'manage every source you\'ve made, import/export them, and see '
                'what\'s supported — plus a check for whether a site is covered'),
            _ChangelogItem('Light novel BROWSING now works — known novel sites '
                '(250+, incl. Madara & LightNovel-WP themes) populate their '
                'popular/latest lists, not just the reader'),
            _ChangelogItem('MangaDex support — create a MangaDex source in '
                'RepoForge and browse/read via its official API'),
            _ChangelogItem('More manga engines auto-detected: HeanCMS (Reaper-style '
                'API sites) and MMRCMS — they generate working sources now'),
            _ChangelogItem('Read light novels — create Novel sources and read '
                'chapters in a clean text reader (font sizing, chapter nav)'),
            _ChangelogItem('FlameComics now detected correctly (was bouncing '
                'between KeyoApp and custom) — the source loads properly'),
            _ChangelogItem('WordPress/Madara novel & manga sites detected more '
                'reliably; broader chapter-text selectors for novel sites'),
            _ChangelogItem('Create sources from any URL — for HTML sites AND '
                'JSON-API sites (e.g. Asura/KeyoApp) (RepoForge)'),
            _ChangelogItem('Generated sources try every known selector (1220-site '
                'knowledge base) — more sites work first-try'),
            _ChangelogItem('RepoForge now generates tube/video sources (e.g. '
                'xVideos); browse tabs adapt to what the source supports'),
            _ChangelogItem('Video sources get a Categories tab — tap a category '
                'to browse its videos, back to the list anytime'),
            _ChangelogItem('Accurate Madara + MangaThemesia source generation '
                '(AJAX chapters, JSON reader pages) — ~245 more sites work'),
            _ChangelogItem('AES crypto + script unpacking so more JS extensions '
                'work out of the box'),
            _ChangelogItem('Export chapters to PDF; import single CBZ/PDF files'),
            _ChangelogItem('JS video sources can now play (getVideoList wired up)'),
            _ChangelogItem('Fixed JS source loading (DOM selector compatibility)'),
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
