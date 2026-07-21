import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/providers/source_provider.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import 'widgets/sources_tab_widget.dart';
import 'widgets/extensions_tab_widget.dart';
import 'widgets/repo_settings_page.dart';
import 'widgets/local_sources_tab_widget.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSearchActive = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight + 48),
          child: _buildAppBar(context, cs),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            SourcesTabWidget(searchQuery: _searchQuery),
            ExtensionsTabWidget(searchQuery: _searchQuery),
            LocalSourcesTabWidget(searchQuery: _searchQuery),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, ColorScheme cs) {
    return Container(
      color: cs.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top row: title/search + action buttons
            SizedBox(
              height: kToolbarHeight,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  // Title or search field
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: AppTheme.standard,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: _isSearchActive
                          ? _buildSearchField(cs)
                          : Align(
                              key: const ValueKey('title'),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Browse',
                                style: GoogleFonts.manrope(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                    ),
                  ),
                  // Action buttons (tab-dependent)
                  if (_tabController.index == 0)
                    _buildActionButton(
                      icon: Icons.travel_explore_rounded,
                      color: cs.primary,
                      onTap: () => Navigator.pushNamed(
                          context, AppRoutes.globalSearch),
                      tooltip: 'Global search',
                    ),
                  if (_tabController.index == 1)
                    _buildActionButton(
                      icon: Icons.refresh_rounded,
                      color: cs.primary,
                      onTap: () {
                        context.read<SourceProvider>().refreshRepos();
                        AppTheme.showSnackBar(context, 'Refreshing repos...');
                      },
                      tooltip: 'Refresh repos',
                    ),
                  _buildActionButton(
                    icon: _isSearchActive
                        ? Icons.close_rounded
                        : Icons.search_rounded,
                    color: cs.onSurface,
                    onTap: () {
                      setState(() {
                        _isSearchActive = !_isSearchActive;
                        if (!_isSearchActive) {
                          _searchController.clear();
                          _searchQuery = '';
                        }
                      });
                    },
                    tooltip: 'Search',
                  ),
                  if (_tabController.index == 1)
                    _buildActionButton(
                      icon: Icons.auto_fix_high_rounded,
                      color: cs.primary,
                      onTap: () async {
                        final provider = context.read<SourceProvider>();
                        await Navigator.pushNamed(
                            context, AppRoutes.repoForgeHub);
                        provider.refreshRepos();
                      },
                      tooltip: 'RepoForge — build & manage sources',
                    ),
                  if (_tabController.index == 1)
                    _buildActionButton(
                      icon: Icons.add_rounded,
                      color: cs.onSurface,
                      onTap: () => _showRepoSettings(context),
                      tooltip: 'Add repo',
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            // Tab bar
            TabBar(
              controller: _tabController,
              labelColor: cs.primary,
              unselectedLabelColor: cs.outline,
              indicatorColor: cs.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              dividerColor: cs.surfaceContainerHighest,
              tabs: const [
                Tab(text: 'Sources'),
                Tab(text: 'Extensions'),
                Tab(text: 'Local'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(ColorScheme cs) {
    return Container(
      key: const ValueKey('search'),
      height: 38,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: GoogleFonts.manrope(fontSize: 13, color: cs.onSurface),
        // Centre the text against the fixed 38px container rather than relying
        // on a hardcoded vertical padding: iOS font metrics (ascent/descent)
        // differ from Android's, so `vertical: 9` sat the text off-centre there.
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: 'Search extensions & sources...',
          hintStyle: GoogleFonts.manrope(fontSize: 13, color: cs.outline),
          prefixIcon: Icon(Icons.search_rounded, size: 16, color: cs.outline),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          filled: false,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          splashColor: Theme.of(context).colorScheme.primary.withAlpha(26),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }

  void _showRepoSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RepoSettingsPage(),
    );
  }
}
