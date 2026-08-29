import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'core/models/manga_model.dart';
import 'core/models/chapter_model.dart';
import 'core/models/category_model.dart';
import 'package:rhttp/rhttp.dart';
import 'core/services/webview_service.dart';
import 'core/services/cf_flaresolverr_server.dart';
import 'core/services/app_logger.dart';
import 'core/services/crash_reporter.dart';
import 'core/providers/source_provider.dart';
import 'core/providers/library_provider.dart';
import 'core/providers/tracking_provider.dart';
import 'core/providers/vault_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/download_provider.dart';
import 'core/providers/library_type_provider.dart';
import 'core/services/library_update_service.dart';
import 'core/services/backup_service.dart';
import 'core/services/app_navigator.dart';
import 'core/services/secure_store.dart';
import 'theme/app_theme.dart';
import 'routes/app_routes.dart';
import 'widgets/app_navigation.dart';
import 'widgets/library_type_menu.dart';
import 'presentation/library_screen/library_screen.dart';
import 'presentation/updates_screen/updates_screen.dart';
import 'presentation/browse_screen/browse_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Route uncaught Dart errors into the in-app error log. Native crashes (the
  // embedded JVM aborting) kill the process before Dart runs, so those are
  // recovered from the JVM's crash files on the next launch by CrashReporter below.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logger.error('Flutter error: ${details.exceptionAsString()}',
        category: LogCategory.general, detail: details.stack?.toString());
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    logger.error('Uncaught error: $error',
        category: LogCategory.general, detail: stack.toString());
    return true;
  };

  MediaKit.ensureInitialized();
  // Hive storage location. On mobile, initFlutter() uses
  // getApplicationDocumentsDirectory(), which is an app-private sandbox — the
  // right place. On desktop that SAME call resolves to the user's shared
  // Documents folder, so initFlutter() would drop library_*.hive files straight
  // into Documents (visible, un-sandboxed, and shared with any other Hive app
  // using the same box names). Point desktop at the app-private support dir
  // instead — %APPDATA%\Roaming\<app> on Windows — so the library lives with
  // the app and a reinstall/uninstall governs it. Mobile keeps initFlutter() so
  // existing installs' data stays exactly where it already is.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final supportDir = await getApplicationSupportDirectory();
    Hive.init(supportDir.path);
  } else {
    await Hive.initFlutter();
  }
  Hive.registerAdapter(LibraryMangaAdapter());
  Hive.registerAdapter(LibraryChapterAdapter());
  Hive.registerAdapter(CategoryAdapter());
  // Must run before any credential-bearing box is opened — providers below
  // read SecureStore.cipher during their initialize().
  await SecureStore.initialize();
  // Initialize rhttp (Rust HTTP client with Chrome TLS fingerprint)
  await Rhttp.init();
  // Initialize WebView environment for Cloudflare cookie extraction
  await initWebViewEnvironment();
  // Loopback FlareSolverr endpoint so the embedded JVM's CloudflareInterceptor
  // can clear Cloudflare through the same device WebView (Kotlin sources).
  await CfFlareSolverrServer.instance.start();
  // If a previous session crashed natively (e.g. the extension engine aborting),
  // surface its report in the in-app error log now.
  await CrashReporter.reportPreviousCrash();
  // Background isolate starts lazily on first use
  // Don't start here — Windows may crash on Isolate.spawn during init
  runApp(const MangaReaderApp());
}

class MangaReaderApp extends StatelessWidget {
  const MangaReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => SourceProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => TrackingProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => VaultProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => LibraryTypeProvider()..initialize()),
        ChangeNotifierProvider(create: (ctx) {
          final dp = DownloadProvider()..initialize();
          // Wire source provider reference after build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            dp.sourceProvider = ctx.read<SourceProvider>();
          });
          return dp;
        }),
      ],
      child: Consumer<ThemeProvider>(
        builder: (_, themeProvider, __) {
          return MaterialApp(
            title: 'Foxlations',
            navigatorKey: rootNavigatorKey,
            scaffoldMessengerKey: rootMessengerKey,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme(
                primaryColor: themeProvider.primaryColor(Brightness.light)),
            darkTheme: AppTheme.darkTheme(
                primaryColor: themeProvider.primaryColor(Brightness.dark)),
            themeMode: themeProvider.themeMode,
            home: const AppShell(),
            navigatorObservers: [routeObserver],
            onGenerateRoute: AppRoutes.onGenerateRoute,
            // Wrap the entire app in a ColorFiltered when invert colors is
            // enabled in Appearance settings. The matrix is the standard
            // RGB invert; alpha is preserved.
            builder: (context, child) {
              if (!themeProvider.invertColors || child == null) return child ?? const SizedBox.shrink();
              return ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  -1,  0,  0, 0, 255,
                   0, -1,  0, 0, 255,
                   0,  0, -1, 0, 255,
                   0,  0,  0, 1,   0,
                ]),
                child: child,
              );
            },
          );
        },
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  int _libraryTapCount = 0;
  DateTime _lastLibraryTap = DateTime(2000);
  int _updatesBadge = 0;

  final _screens = const [
    LibraryScreen(),
    UpdatesScreen(),
    BrowseScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUpdatesBadge();
    // Run any due automatic backup once the library boxes have opened, then a
    // due automatic library update (Settings > Library > Update frequency). Both
    // wait for the providers to finish loading from disk.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 4));
      try {
        await BackupService().maybeRunAuto();
      } catch (_) {}
      await _maybeAutoUpdateLibrary();
    });
  }

  /// Runs a library update if one is due per the frequency / Wi-Fi / charging
  /// settings. Best-effort and silent: an auto-update must never interrupt the
  /// user or crash the app. Called on launch and on resume.
  Future<void> _maybeAutoUpdateLibrary() async {
    try {
      if (!await LibraryUpdateService.shouldAutoUpdate()) return;
      if (!mounted) return;
      final lib = context.read<LibraryProvider>();
      final src = context.read<SourceProvider>();
      if (lib.manga.isEmpty) return; // Providers not loaded yet, or empty library.
      await LibraryUpdateService.checkForUpdates(
          libraryProvider: lib, sourceProvider: src);
      if (mounted) _loadUpdatesBadge();
    } catch (_) {
      // Swallow — foreground auto-update is a convenience, not a guarantee.
    }
  }

  void _showVaultPasswordDialog(VaultProvider vault) {
    final controller = TextEditingController();
    final cs = Theme.of(context).colorScheme;
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.shield_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Text('Vault Password', style: GoogleFonts.manrope(
                fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface),
              decoration: InputDecoration(
                hintText: 'Enter password',
                hintStyle: GoogleFonts.manrope(fontSize: 14, color: cs.outline),
                errorText: error,
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 18, color: cs.outline),
              ),
              onSubmitted: (_) async {
                // unlock() derives the key and opens the encrypted boxes, so
                // it's async (~1s) and a wrong password simply can't decrypt.
                setDialogState(() => error = null);
                if (await vault.unlock(controller.text)) {
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  vault.enterVault();
                } else {
                  setDialogState(() => error = 'Wrong password');
                }
              },
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w600, color: cs.outline))),
            FilledButton(
              onPressed: () async {
                // unlock() derives the key and opens the encrypted boxes, so
                // it's async (~1s) and a wrong password simply can't decrypt.
                setDialogState(() => error = null);
                if (await vault.unlock(controller.text)) {
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  vault.enterVault();
                } else {
                  setDialogState(() => error = 'Wrong password');
                }
              },
              style: FilledButton.styleFrom(backgroundColor: cs.primary),
              child: Text('Unlock', style: GoogleFonts.manrope(fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }

  Future<void> _loadUpdatesBadge() async {
    // Honour Settings > Library > "Show update count". When off, keep the badge
    // at 0 so the Updates tab shows no number. Re-read each time (this runs on
    // every tab change) so toggling the setting takes effect without a restart.
    final prefs = await SharedPreferences.getInstance();
    final show = prefs.getBool('lib_show_update_count') ?? true;
    final count = show ? await LibraryUpdateService.getUnreadCount() : 0;
    if (mounted) setState(() => _updatesBadge = count);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Exit vault when app is paused (device locked, backgrounded, etc.)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      context.read<VaultProvider>().exitVault();
    }
    // On return to the foreground, check whether a library update has come due.
    if (state == AppLifecycleState.resumed) {
      _maybeAutoUpdateLibrary();
    }
  }

  void _onTabChanged(int index) {
    if (index == 3) {
      Navigator.pushNamed(context, AppRoutes.settings);
      return;
    }

    // Track rapid taps on Library tab for vault activation
    if (index == 0 && _currentIndex == 0) {
      final now = DateTime.now();
      if (now.difference(_lastLibraryTap).inMilliseconds < 2000) {
        _libraryTapCount++;
      } else {
        _libraryTapCount = 1;
      }
      _lastLibraryTap = now;

      final vault = context.read<VaultProvider>();
      if (vault.vaultEnabled && _libraryTapCount >= 6 && _libraryTapCount < 8) {
        final remaining = 8 - _libraryTapCount;
        ScaffoldMessenger.of(context).clearSnackBars();
        AppTheme.showSnackBar(context,
            '$remaining more tap${remaining == 1 ? '' : 's'} to ${vault.vaultActive ? 'exit' : 'enter'} vault',
            duration: const Duration(milliseconds: 800));
      }
      if (_libraryTapCount >= 8 && vault.vaultEnabled) {
        _libraryTapCount = 0;
        ScaffoldMessenger.of(context).clearSnackBars();
        if (vault.vaultActive) {
          vault.exitVault();
        } else {
          if (vault.hasPassword) {
            _showVaultPasswordDialog(vault);
          } else {
            vault.enterVault();
          }
        }
        return;
      }
    } else {
      _libraryTapCount = 0;
    }

    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    final isVault = vault.vaultActive;
    final contentType = context.watch<LibraryTypeProvider>().type;
    // Browse-tab badge: installed extensions with a newer version, scoped to the
    // current space (vault sources only in vault mode, non-vault sources otherwise).
    final browseBadge = context
        .watch<SourceProvider>()
        .updatesForContext(
            vaultActive: vault.vaultActive, vaultIds: vault.vaultSourceIds)
        .length;
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentIndex,
        onTap: (i) { _onTabChanged(i); if (i != 1) _loadUpdatesBadge(); },
        isVaultMode: isVault,
        updatesBadge: _updatesBadge,
        browseBadge: browseBadge,
        contentType: contentType,
        // Long-press the Library tab to switch between Manga / Anime / Novels;
        // the bubble anchors just above the tab (anchor = its global rect).
        onLibraryLongPress: (anchor) => showLibraryTypeBubble(context, anchor),
      ),
    );
  }
}
