import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/providers/library_type_provider.dart';
import '../theme/app_theme.dart';

/// Icons for each content type, mirroring the Library tab's own icon set.
class _TypeIcon {
  final IconData icon;
  final IconData active;
  const _TypeIcon(this.icon, this.active);
}

const Map<String, _TypeIcon> _kTypeIcons = {
  'manga': _TypeIcon(
      Icons.collections_bookmark_outlined, Icons.collections_bookmark),
  'anime': _TypeIcon(Icons.smart_display_outlined, Icons.smart_display),
  'novel': _TypeIcon(Icons.menu_book_outlined, Icons.menu_book),
};

/// Returns the tab icon for [type] (active or inactive), used both here and by
/// the bottom nav so the Library tab reflects the current selection.
IconData libraryTypeIcon(String type, {bool active = false}) {
  final set = _kTypeIcons[type] ?? _kTypeIcons['manga']!;
  return active ? set.active : set.icon;
}

/// Pops up a small picker — styled like the bottom nav bar — that lets the user
/// switch the Library between Manga, Anime and Light Novels. Long-pressing the
/// Library tab opens it. The choice is persisted by [LibraryTypeProvider].
Future<void> showLibraryTypeMenu(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withAlpha(77),
    builder: (sheetContext) => const _LibraryTypeMenu(),
  );
}

class _LibraryTypeMenu extends StatelessWidget {
  const _LibraryTypeMenu();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = context.watch<LibraryTypeProvider>().type;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(77),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outline.withAlpha(128),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Text('SHOW IN LIBRARY',
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: cs.outline,
              )),
          const SizedBox(height: 6),
          SizedBox(
            height: 64,
            child: Row(
              children: LibraryTypeProvider.types.map((type) {
                final isActive = type == selected;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      await context.read<LibraryTypeProvider>().setType(type);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                isActive ? cs.primary.withAlpha(26) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            libraryTypeIcon(type, active: isActive),
                            size: 22,
                            color: isActive ? cs.primary : cs.outline,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          LibraryTypeProvider.label(type),
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w500,
                            color: isActive ? cs.primary : cs.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
