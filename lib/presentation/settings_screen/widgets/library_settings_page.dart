import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/providers/library_provider.dart';
import '../../../theme/app_theme.dart';
import 'source_migrate_screen.dart';

class LibrarySettingsPage extends StatefulWidget {
  const LibrarySettingsPage({super.key});

  @override
  State<LibrarySettingsPage> createState() => _LibrarySettingsPageState();
}

class _LibrarySettingsPageState extends State<LibrarySettingsPage> {
  bool _hideEmptyCategories = false;
  bool _wifiOnly = true;
  bool _chargingOnly = false;
  String _updateFrequency = 'Manual';
  bool _skipNotStarted = false;
  bool _showUpdateCount = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hideEmptyCategories = prefs.getBool('lib_hide_empty_cats') ?? false;
      _wifiOnly = prefs.getBool('lib_update_wifi_only') ?? true;
      _chargingOnly = prefs.getBool('lib_update_charging_only') ?? false;
      _updateFrequency = prefs.getString('lib_update_frequency') ?? 'Manual';
      _skipNotStarted = prefs.getBool('lib_skip_not_started') ?? false;
      _showUpdateCount = prefs.getBool('lib_show_update_count') ?? true;
    });
  }

  Future<void> _save(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
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
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: cs.onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Library',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.only(
            top: 8, bottom: 8 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          _SectionHeader(title: 'Categories'),
          _NavTile(
            icon: Icons.category_rounded,
            iconColor: cs.primary,
            title: 'Edit Categories',
            subtitle: 'Add, remove, and reorder categories',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _EditCategoriesPage()),
            ),
          ),
          _SwitchTile(
            icon: Icons.folder_off_rounded,
            iconColor: cs.primary,
            title: 'Hide Empty Categories',
            subtitle: 'Only show categories with manga',
            value: _hideEmptyCategories,
            onChanged: (v) { setState(() => _hideEmptyCategories = v); _save('lib_hide_empty_cats', v); },
          ),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Global Update'),
          _ChoiceTile(
            icon: Icons.schedule_rounded,
            iconColor: AppTheme.success,
            title: 'Update Frequency',
            value: _updateFrequency,
            options: const [
              'Manual',
              'Every 12 hours',
              'Daily',
              'Every 2 days',
              'Weekly',
            ],
            onChanged: (v) { setState(() => _updateFrequency = v); _save('lib_update_frequency', v); },
          ),
          _SwitchTile(
            icon: Icons.wifi_rounded,
            iconColor: AppTheme.success,
            title: 'Wi-Fi Only',
            subtitle: 'Only update on Wi-Fi connections',
            value: _wifiOnly,
            onChanged: (v) { setState(() => _wifiOnly = v); _save('lib_update_wifi_only', v); },
          ),
          _SwitchTile(
            icon: Icons.battery_charging_full_rounded,
            iconColor: AppTheme.success,
            title: 'Only While Charging',
            subtitle: 'Only update when device is charging',
            value: _chargingOnly,
            onChanged: (v) { setState(() => _chargingOnly = v); _save('lib_update_charging_only', v); },
          ),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Update Restrictions'),
          _SwitchTile(
            icon: Icons.visibility_off_rounded,
            iconColor: AppTheme.warning,
            title: 'Skip Not Started',
            subtitle: 'Skip manga with no reading progress',
            value: _skipNotStarted,
            onChanged: (v) { setState(() => _skipNotStarted = v); _save('lib_skip_not_started', v); },
          ),
          _SwitchTile(
            icon: Icons.notifications_active_rounded,
            iconColor: AppTheme.warning,
            title: 'Show New Chapter Count',
            subtitle: 'Show badge on library manga cards',
            value: _showUpdateCount,
            onChanged: (v) { setState(() => _showUpdateCount = v); _save('lib_show_update_count', v); },
          ),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Data'),
          _NavTile(
            icon: Icons.swap_horiz_rounded,
            iconColor: cs.primary,
            title: 'Migrate a Source',
            subtitle: 'Move every entry from one source to another',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SourceMigrateScreen()),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Nav Tile (click to navigate) ────────────────────────────
class _NavTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.iconColor,
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
                color: iconColor.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  Text(subtitle,
                      style:
                          GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.outline, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Edit Categories Page ────────────────────────────────────
class _EditCategoriesPage extends StatelessWidget {
  const _EditCategoriesPage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
        title: Text('Edit Categories',
            style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        child: const Icon(Icons.add_rounded),
      ),
      body: Consumer<LibraryProvider>(
        builder: (context, library, _) {
          final categories = library.categories;

          if (categories.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.category_outlined,
                      size: 64, color: cs.outline.withAlpha(128)),
                  const SizedBox(height: 16),
                  Text('No categories',
                      style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  const SizedBox(height: 8),
                  Text('Tap + to add a category',
                      style:
                          GoogleFonts.manrope(fontSize: 13, color: cs.outline)),
                ],
              ),
            );
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
            buildDefaultDragHandles: false,
            itemCount: categories.length,
            proxyDecorator: (child, index, animation) {
              return Material(
                elevation: 4,
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                child: child,
              );
            },
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              final names = categories.map((c) => c.name).toList();
              final item = names.removeAt(oldIndex);
              names.insert(newIndex, item);
              library.reorderCategories(names);
            },
            itemBuilder: (context, index) {
              final cat = categories[index];
              return _CategoryTile(
                key: ValueKey(cat.name),
                name: cat.name,
                index: index,
                onRename: () =>
                    _showRenameDialog(context, library, cat.name),
                onDelete: () =>
                    _showDeleteConfirm(context, library, cat.name),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final library = context.read<LibraryProvider>();
    final controller = TextEditingController();
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        title: Text('New Category',
            style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: 'Category name',
            hintStyle: GoogleFonts.manrope(fontSize: 14, color: cs.outline),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                borderSide: BorderSide.none),
          ),
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isNotEmpty) {
              library.addCategory(name);
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600, color: cs.outline)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                library.addCategory(name);
                Navigator.pop(ctx);
              }
            },
            child: Text('Add',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700, color: cs.primary)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(
      BuildContext context, LibraryProvider library, String oldName) {
    final controller = TextEditingController(text: oldName);
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        title: Text('Rename Category',
            style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: 'Category name',
            hintStyle: GoogleFonts.manrope(fontSize: 14, color: cs.outline),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                borderSide: BorderSide.none),
          ),
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isNotEmpty && name != oldName) {
              library.renameCategory(oldName, name);
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600, color: cs.outline)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty && name != oldName) {
                library.renameCategory(oldName, name);
                Navigator.pop(ctx);
              }
            },
            child: Text('Save',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700, color: cs.primary)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(
      BuildContext context, LibraryProvider library, String name) {
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        title: Text('Delete Category',
            style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        content: Text(
            'Are you sure you want to delete "$name"? Manga in this category will not be removed from your library.',
            style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600, color: cs.outline)),
          ),
          TextButton(
            onPressed: () {
              library.removeCategory(name);
              Navigator.pop(ctx);
            },
            child: Text('Delete',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700, color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

// ── Category Tile (used in Edit Categories page) ────────────
class _CategoryTile extends StatelessWidget {
  final String name;
  final int index;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _CategoryTile({
    super.key,
    required this.name,
    required this.index,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(Icons.drag_handle_rounded,
                  size: 20, color: cs.outline),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface)),
          ),
          IconButton(
            icon: Icon(Icons.edit_rounded, size: 18, color: cs.outline),
            onPressed: onRename,
            splashRadius: 20,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                size: 18, color: AppTheme.error),
            onPressed: onDelete,
            splashRadius: 20,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ── Shared Widgets ───────────────────────────────────────────
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

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              color: iconColor.withAlpha(25),
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
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: cs.onPrimary,
            activeTrackColor: cs.primary,
          ),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _ChoiceTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _showPicker(context),
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
                color: iconColor.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: cs.outline,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                color: cs.outline, size: 20),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLarge),
        ),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            Divider(color: cs.outlineVariant),
            ...options.map((opt) {
              final isSelected = opt == value;
              return InkWell(
                onTap: () {
                  onChanged(opt);
                  Navigator.pop(context);
                },
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusMedium),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primary.withAlpha(26)
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          opt,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_rounded,
                            size: 18, color: cs.primary),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
