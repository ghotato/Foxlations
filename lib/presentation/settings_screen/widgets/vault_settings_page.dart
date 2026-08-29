import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/vault_provider.dart';
import '../../../core/providers/source_provider.dart';
import '../../../theme/app_theme.dart';
import 'vault_contents_page.dart';

class VaultSettingsPage extends StatelessWidget {
  const VaultSettingsPage({super.key});

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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Text('Vault',
                style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
          ],
        ),
      ),
      body: Consumer<VaultProvider>(
        builder: (context, vault, _) {
          return ListView(
            padding: EdgeInsets.only(
                top: 8, bottom: 8 + MediaQuery.of(context).viewPadding.bottom),
            children: [
              _SectionHeader(title: 'Access'),
              _SwitchTile(
                icon: Icons.shield_rounded,
                iconColor: cs.primary,
                title: 'Enable Vault',
                subtitle:
                    'Allow access to the hidden vault by tapping Library 8 times',
                value: vault.vaultEnabled,
                onChanged: (v) => vault.setVaultEnabled(v),
              ),
              const SizedBox(height: 8),
              _SectionHeader(title: 'Security'),
              _NavTile(
                icon: Icons.lock_rounded,
                iconColor: AppTheme.warning,
                title: vault.hasPassword ? 'Change Password' : 'Set Password',
                subtitle: vault.hasPassword
                    ? 'Password is set — tap to change or remove'
                    : 'Protect vault access with a password',
                onTap: () => _showPasswordDialog(context, vault),
              ),
              const SizedBox(height: 8),
              _SectionHeader(title: 'Vault Categories'),
              _NavTile(
                icon: Icons.category_rounded,
                iconColor: AppTheme.secondary,
                title: 'Edit Vault Categories',
                subtitle: 'Add, remove, and reorder vault categories',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const _EditVaultCategoriesPage()),
                ),
              ),
              const SizedBox(height: 8),
              _SectionHeader(title: 'Contents'),
              _NavTile(
                icon: Icons.swap_vert_rounded,
                iconColor: cs.primary,
                title: 'Manage Vault Contents',
                subtitle: 'Move manga, anime or novels in and out of the vault',
                onTap: () {
                  // Moving requires the vault unlocked, so prompt first when a
                  // password is set and it isn't open yet.
                  if (vault.hasPassword && !vault.isUnlocked) {
                    AppTheme.showSnackBar(
                        context, 'Unlock the vault first (tap in from the library)');
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VaultContentsPage()),
                  );
                },
              ),
              const SizedBox(height: 8),
              _SectionHeader(title: 'Hidden Sources'),
              _NavTile(
                icon: Icons.visibility_off_rounded,
                iconColor: cs.primary,
                title: 'Vault-Only Sources',
                subtitle: '${vault.vaultSourceIds.length} source${vault.vaultSourceIds.length == 1 ? '' : 's'} hidden',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const _HiddenSourcesPage()),
                ),
              ),
              const SizedBox(height: 8),
              _SectionHeader(title: 'Info'),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(15),
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: cs.primary.withAlpha(40)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'The vault is a hidden library with its own categories and manga. '
                          'Tap the Library tab 8 times rapidly to toggle vault mode. '
                          'Vault manga are stored separately and never appear in your main library.',
                          style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: cs.onSurface,
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  void _showPasswordDialog(BuildContext context, VaultProvider vault) {
    final cs = Theme.of(context).colorScheme;
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: cs.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(vault.hasPassword ? 'Change Password' : 'Set Password',
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              if (vault.hasPassword)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: currentController,
                    obscureText: true,
                    style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Current password',
                      hintStyle: GoogleFonts.manrope(fontSize: 14, color: cs.outline),
                      filled: true, fillColor: cs.surfaceContainerHighest,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              TextField(
                controller: newController,
                obscureText: true,
                style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: 'New password (leave empty to remove)',
                  hintStyle: GoogleFonts.manrope(fontSize: 14, color: cs.outline),
                  filled: true, fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmController,
                obscureText: true,
                style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: 'Confirm new password',
                  hintStyle: GoogleFonts.manrope(fontSize: 14, color: cs.outline),
                  errorText: error,
                  filled: true, fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600, color: cs.outline))),
              FilledButton(
                onPressed: () async {
                  // Verifying now derives the key and opens the encrypted
                  // boxes, so it's async and takes ~1s.
                  if (vault.hasPassword &&
                      !await vault.unlock(currentController.text)) {
                    setDialogState(() => error = 'Current password is wrong');
                    return;
                  }
                  final newPw = newController.text;
                  final confirmPw = confirmController.text;
                  if (newPw.isNotEmpty && newPw != confirmPw) {
                    setDialogState(() => error = 'Passwords do not match');
                    return;
                  }
                  setDialogState(() => error = newPw.isEmpty
                      ? 'Removing encryption…'
                      : 'Encrypting vault…');
                  await vault.setPassword(newPw.isEmpty ? null : newPw);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!context.mounted) return;
                  AppTheme.showSnackBar(
                      context,
                      newPw.isEmpty
                          ? 'Password removed — vault is no longer encrypted'
                          : 'Password set — vault encrypted');
                },
                style: FilledButton.styleFrom(backgroundColor: cs.primary),
                child: Text('Save', style: GoogleFonts.manrope(fontWeight: FontWeight.w700))),
            ],
          );
        },
      ),
    );
  }
}

// ── Edit Vault Categories Page ──────────────────────────────
class _EditVaultCategoriesPage extends StatelessWidget {
  const _EditVaultCategoriesPage();

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
        title: Text('Vault Categories',
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
      body: Consumer<VaultProvider>(
        builder: (context, vault, _) {
          final categories = vault.categories;

          if (categories.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.category_outlined,
                      size: 64, color: cs.outline.withAlpha(128)),
                  const SizedBox(height: 16),
                  Text('No vault categories',
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
              vault.reorderCategories(names);
            },
            itemBuilder: (context, index) {
              final cat = categories[index];
              return _CategoryTile(
                key: ValueKey(cat.name),
                name: cat.name,
                index: index,
                onRename: () => _showRenameDialog(context, vault, cat.name),
                onDelete: () => _showDeleteConfirm(context, vault, cat.name),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final vault = context.read<VaultProvider>();
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
              vault.addCategory(name);
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
                vault.addCategory(name);
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
      BuildContext context, VaultProvider vault, String oldName) {
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
              vault.renameCategory(oldName, name);
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
                vault.renameCategory(oldName, name);
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
      BuildContext context, VaultProvider vault, String name) {
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
            'Are you sure you want to delete "$name"? Manga in this category will not be removed from the vault.',
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
              vault.removeCategory(name);
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

// ── Shared Widgets ──────────────────────────────────────────
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(title.toUpperCase(),
          style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: cs.primary)),
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
      child: Row(children: [
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
                  style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: cs.onPrimary,
          activeTrackColor: cs.primary,
        ),
      ]),
    );
  }
}

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
                      style: GoogleFonts.manrope(
                          fontSize: 12, color: cs.outline)),
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

// ── Hidden Sources Page ────────────────────────────────────
class _HiddenSourcesPage extends StatefulWidget {
  const _HiddenSourcesPage();

  @override
  State<_HiddenSourcesPage> createState() => _HiddenSourcesPageState();
}

class _HiddenSourcesPageState extends State<_HiddenSourcesPage> {
  String _query = '';

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
        title: Text('Vault-Only Sources',
            style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
      ),
      body: Consumer2<SourceProvider, VaultProvider>(
        builder: (context, sourceProvider, vault, _) {
          var installed = sourceProvider.installedSources;
          if (_query.isNotEmpty) {
            final q = _query.toLowerCase();
            installed = installed.where((s) => s.source.name.toLowerCase().contains(q)).toList();
          }
          if (installed.isEmpty && _query.isEmpty) {
            return Center(child: Text('No installed sources',
                style: GoogleFonts.manrope(fontSize: 14, color: cs.outline)));
          }

          return ListView(
            padding: EdgeInsets.only(
                top: 8, bottom: 8 + MediaQuery.of(context).viewPadding.bottom),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Toggle sources to make them only visible in vault mode.',
                  style: GoogleFonts.manrope(fontSize: 12, color: cs.outline, height: 1.5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Search sources...',
                    hintStyle: GoogleFonts.manrope(fontSize: 14, color: cs.outline),
                    prefixIcon: Icon(Icons.search_rounded, size: 20, color: cs.outline),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              ...installed.map((s) {
                final source = s.source;
                final isHidden = vault.isSourceInVault(source.id);
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isHidden ? cs.primary.withAlpha(15) : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: isHidden ? Border.all(color: cs.primary.withAlpha(80)) : null,
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: cs.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(child: Text(
                        source.name.isNotEmpty ? source.name[0].toUpperCase() : '?',
                        style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: cs.primary),
                      )),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(source.name, style: GoogleFonts.manrope(
                            fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                        Text(source.baseUrl, style: GoogleFonts.manrope(
                            fontSize: 11, color: cs.outline), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    )),
                    Switch(
                      value: isHidden,
                      onChanged: (_) => vault.toggleVaultSource(source.id),
                      activeThumbColor: cs.onPrimary,
                      activeTrackColor: cs.primary,
                    ),
                  ]),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
