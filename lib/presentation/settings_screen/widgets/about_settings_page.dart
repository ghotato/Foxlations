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
            _ChangelogItem('Long-pressing a chapter now opens a menu — Bookmark, '
                'Mark all below as read, Mark chapter as read or unread, and '
                'Download — instead of only toggling a bookmark.'),
            _ChangelogItem('A title\'s three-dots menu now has the full set of '
                'actions: Edit categories, Notes, Migrate, Refresh, Select '
                'chapters, Remove from library, and Open in browser.'),
            _ChangelogItem('"Select chapters" turns the chapter list into a '
                'multi-select. Tap to pick chapters, then use the bottom bar to '
                'bookmark, mark all below as read, mark read or unread, or '
                'download the whole selection at once.'),
            _ChangelogItem('Titles can hold a note now. Add one from the '
                'three-dots "Notes" menu — it shows as a card under the '
                'description and taps to edit.'),
            _ChangelogItem('Migration can carry your tracking across. A new '
                '"Tracking" toggle re-binds the entry\'s MAL / AniList / Kitsu '
                'links to the new source so it keeps syncing.'),
            _ChangelogItem('Bulk migration is smoother. While you pick a target '
                'for one entry, the next entry\'s search runs in the background, '
                'so the following screen opens with results already loaded. '
                'Results also fill in as each source answers, and one stuck '
                'source can no longer stall the whole batch.'),
            _ChangelogItem('Fixed a grey box on the reading-stats screen. A top '
                'series with a shortened link — common for entries brought in '
                'from another app — was crashing the "Most-Read Series" card, '
                'and a crash renders as a blank grey box. Guarded here and in '
                'one other place with the same fault.'),
            _ChangelogItem('Migrating an entry now asks what to carry over — '
                'read progress, categories, and whether downloaded chapters are '
                'deleted. A new "Show entry" button opens the candidate on the '
                'other source first so you can check it has the full chapter '
                'list before committing, and "Copy" keeps the original and adds '
                'the other source alongside it.'),
            _ChangelogItem('Migrate now works on a selection: hold to select '
                'entries in your library and tap Migrate to step through them '
                'one at a time, with a counter showing how far along you are. '
                'It goes one by one deliberately — titles differ between '
                'sources, so matching automatically would quietly attach the '
                'wrong series.'),
            _ChangelogItem('Sources you build with RepoForge are now created in '
                'the app\'s own format instead of JavaScript. The JavaScript '
                'ones never worked — the part that fetches a page handed back '
                'a response with no content, so a source came up empty no '
                'matter how well its selectors matched. They\'re now built the '
                'same way the bundled sources are, and tested against live '
                'sites before release. Sources you built earlier will still be '
                'empty; rebuild them from the same site URL and they\'ll work.'),
            _ChangelogItem('RepoForge: a site whose whole card is one big link '
                'no longer comes back empty. The generated code only looked '
                'for a link inside each card, so where the card is itself the '
                'link it found none and discarded every result.'),
            _ChangelogItem('Scrolling the library category strip is smooth '
                'again — each chip was re-resolving its font on every frame of '
                'a drag, which made the whole row stutter.'),
            _ChangelogItem('Library "Items per row" now actually goes to 6. '
                'The option offered up to six, but the grid quietly capped at '
                'four on a phone, so picking five or six changed the number on '
                'screen and nothing else.'),
            _ChangelogItem('RepoForge understands five more site layouts — '
                'MadTheme, WPComics, ZeistManga, FMReader and nhentai-style '
                'galleries. They were already recognised by name, but nothing '
                'was known about how they arrange their pages, so a generated '
                'source fell back to generic guesses: usually finding nothing, '
                'occasionally picking up an advert instead of a title.'),
            _ChangelogItem('RepoForge: search now works in generated sources '
                'for sites whose results page is laid out differently from '
                'their browse page. Only the browse layout was recognised, so '
                'a generated source could list titles perfectly and then find '
                'nothing at all for every search.'),
            _ChangelogItem('Anime and light-novel sources from an added repo '
                'now show up. Repos publish those in a separate list next to '
                'the manga one, and the app only recognised one exact filename '
                '— so if a repo named its list slightly differently, every '
                'anime and novel source in it was invisible, with no error to '
                'explain why.'),
            _ChangelogItem('RepoForge: cover images resolve far more often. '
                'Most sites load covers lazily and keep the real address in '
                'one of several different attributes; only one was being read, '
                'so generated sources showed rows of blank artwork whenever a '
                'site used another.'),
            _ChangelogItem('RepoForge: adverts are no longer listed as manga. '
                'Ad slots dropped into a results grid look like a normal card, '
                'and one was appearing as a title with a blank cover. An entry '
                'now needs both a name and a link to be listed, and titles fall '
                'back to the link\'s tooltip or the cover\'s description rather '
                'than coming through blank.'),
            _ChangelogItem('RepoForge: added the listing layout used by the '
                'Manganato / Mangakakalot / Mangabat family, which had none — '
                'generated sources for those sites now work first try.'),
            _ChangelogItem('New "Request desktop site" option in a source\'s '
                'settings. Some sites send phones a cut-down page with the real '
                'content missing, so the source finds nothing. Turn this on and '
                'it asks for the full desktop page instead — worth trying '
                'whenever a source comes up empty, or opens but lists no '
                'chapters. Sites behind a Cloudflare check are left alone, so '
                'you won\'t have to solve the check again.'),
            _ChangelogItem('RepoForge: Webtoons chapter lists now load once '
                '"Request desktop site" is on, and browsing works whether the '
                'site serves its phone or its desktop layout. The last release '
                'only matched the phone one.'),
            _ChangelogItem('Your private data is now encrypted. Login tokens for '
                'AniList/MyAnimeList/Kitsu are protected by the device keystore, '
                'and the vault is properly encrypted with your password instead '
                'of just hidden. (You\'ll need to reconnect trackers once, and '
                're-enter your vault password to re-encrypt it.)'),
            _ChangelogItem('Hardened the app for its public release: connections '
                'now verify their security certificates, extensions can no '
                'longer be tricked into running hidden code via a crafted source '
                'name or URL, and sources must load over https'),
            _ChangelogItem('RepoForge Scraping Studio: each selector field now '
                'has a searchable list of known selectors to pick from (with a '
                'live count of how many things each one matches), so you don\'t '
                'have to know CSS. The test button is clearer, and "0 matches" '
                'now shows as a gentle "no match" instead of a red error'),
            _ChangelogItem('RepoForge now recognises 60+ more site frameworks '
                'across manga, anime and light novels (Madara, MangaThemesia, '
                'foolslide, GigaViewer, the big novel CMSes, and many more). '
                'When it detects one, it auto-fills the selector slots with what '
                'that framework uses, so you rarely have to type them by hand'),
            _ChangelogItem('RepoForge no longer mislabels sites as an "AniList '
                'API" just because they link to AniList — that detection was '
                'removed (AniList has no readable content to build a source '
                'from), so sites are now identified by their real framework'),
            _ChangelogItem('Clearer error when adding a source that can\'t run: '
                'Tachiyomi/Mihon (Kotlin) repos like keiyoushi aren\'t supported '
                '— Foxlations uses JavaScript/Dart sources — so it now says so '
                'instead of failing with a confusing "main" error'),
            _ChangelogItem('Text all over the app is easier to read — subtitles, '
                'captions, placeholders and dividers were too dim against the '
                'background, and buttons could show white text on a light '
                'colour. Toasts now stand out from the page instead of '
                'blending into it'),
            _ChangelogItem('Reader: loading spinners, error messages and page '
                'placeholders now follow your chosen background colour — on a '
                'white background they were white on white, so invisible'),
            _ChangelogItem('Check for Updates actually checks now — it tells '
                'you when a new build is out and what changed. Android can '
                'download it directly; on iPhone AltStore handles the update'),
            _ChangelogItem('Restoring a Tachiyomi/Mihon/Tachimanga backup now '
                'links each manga to the right installed source — before, '
                'everything came back with no source and wouldn\'t open'),
            _ChangelogItem('Every source now has its own settings: override the '
                'site address if it changes domain, pin it to the top, or skip '
                'it during global search and library updates'),
            _ChangelogItem('Library can now sort by chapter fetch date, so you '
                'can see which series haven\'t been checked in a while'),
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
