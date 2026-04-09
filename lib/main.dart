import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'core/models/manga_model.dart';
import 'core/models/chapter_model.dart';
import 'core/models/category_model.dart';
import 'package:rhttp/rhttp.dart';
import 'core/services/webview_service.dart';
import 'core/providers/source_provider.dart';
import 'core/providers/library_provider.dart';
import 'core/providers/vault_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/download_provider.dart';
import 'core/services/library_update_service.dart';
import 'theme/app_theme.dart';
import 'routes/app_routes.dart';
import 'widgets/app_navigation.dart';
import 'presentation/library_screen/library_screen.dart';
import 'presentation/updates_screen/updates_screen.dart';
import 'presentation/browse_screen/browse_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(LibraryMangaAdapter());
  Hive.registerAdapter(LibraryChapterAdapter());
  Hive.registerAdapter(CategoryAdapter());
  // Initialize rhttp (Rust HTTP client with Chrome TLS fingerprint)
  await Rhttp.init();
  // Initialize WebView environment for Cloudflare cookie extraction
  await initWebViewEnvironment();
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
        ChangeNotifierProvider(create: (_) => VaultProvider()..initialize()),
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
            title: 'Manga Reader',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme(
                primaryColor: themeProvider.primaryColor(Brightness.light)),
            darkTheme: AppTheme.darkTheme(
                primaryColor: themeProvider.primaryColor(Brightness.dark)),
            themeMode: themeProvider.themeMode,
            home: const AppShell(),
            onGenerateRoute: AppRoutes.onGenerateRoute,
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
              onSubmitted: (_) {
                if (vault.verifyPassword(controller.text)) {
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
              onPressed: () {
                if (vault.verifyPassword(controller.text)) {
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
    final count = await LibraryUpdateService.getUnreadCount();
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
    final isVault = context.watch<VaultProvider>().vaultActive;
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
      ),
    );
  }
}
