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
  // 'all' keeps the classic Library icon, so the default tab looks unchanged.
  'all': _TypeIcon(
      Icons.collections_bookmark_outlined, Icons.collections_bookmark),
  'manga': _TypeIcon(Icons.auto_stories_outlined, Icons.auto_stories),
  'anime': _TypeIcon(Icons.smart_display_outlined, Icons.smart_display),
  'novel': _TypeIcon(Icons.menu_book_outlined, Icons.menu_book),
};

/// Returns the tab icon for [type] (active or inactive), used both here and by
/// the bottom nav so the Library tab reflects the current selection.
IconData libraryTypeIcon(String type, {bool active = false}) {
  final set = _kTypeIcons[type] ?? _kTypeIcons['all']!;
  return active ? set.active : set.icon;
}

const double _kBubbleWidth = 216;

/// Pops up a small bubble — anchored just above the Library tab that was
/// long-pressed — letting the user switch the library between Manga, Anime and
/// Light Novels. Each acts like its own library; the choice is persisted by
/// [LibraryTypeProvider]. [anchor] is the Library tab's global rect, used to
/// position the bubble and its downward pointer over it.
Future<void> showLibraryTypeBubble(BuildContext context, Rect anchor) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Library type',
    barrierColor: Colors.black.withAlpha(40),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, __, ___) => _LibraryTypeBubble(anchor: anchor),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: Align(
          // Scale up from the bottom (toward the tab), so it reads as growing
          // out of the Library button.
          alignment: Alignment.bottomCenter,
          child: ScaleTransition(
            scale: Tween(begin: 0.9, end: 1.0).animate(curved),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        ),
      );
    },
  );
}

class _LibraryTypeBubble extends StatelessWidget {
  final Rect anchor;
  const _LibraryTypeBubble({required this.anchor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final selected = context.watch<LibraryTypeProvider>().type;

    // Horizontal centre of the Library tab, and where the bubble's left edge
    // lands once it's clamped on-screen. The pointer then sits at that centre
    // relative to the bubble.
    final anchorCx = anchor.center.dx;
    final left = (anchorCx - _kBubbleWidth / 2)
        .clamp(8.0, screenW - _kBubbleWidth - 8.0);
    final pointerLeft = (anchorCx - left).clamp(16.0, _kBubbleWidth - 16.0);
    // Sit the bubble's bottom (its pointer tip) a few px above the tab.
    final bottom = (screenH - anchor.top) + 4;

    return Stack(
      children: [
        Positioned(
          left: left,
          bottom: bottom,
          width: _kBubbleWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(60),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final type in LibraryTypeProvider.types)
                        _row(context, cs, type, type == selected),
                    ],
                  ),
                ),
              ),
              // Downward pointer toward the Library tab.
              Padding(
                padding: EdgeInsets.only(left: pointerLeft - 8),
                child: CustomPaint(
                  size: const Size(16, 8),
                  painter: _PointerPainter(cs.surface),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
      BuildContext context, ColorScheme cs, String type, bool isActive) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      onTap: () async {
        await context.read<LibraryTypeProvider>().setType(type);
        if (context.mounted) Navigator.pop(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? cs.primary.withAlpha(26) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                libraryTypeIcon(type, active: isActive),
                size: 20,
                color: isActive ? cs.primary : cs.outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                LibraryTypeProvider.label(type),
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? cs.primary : cs.onSurface,
                ),
              ),
            ),
            if (isActive)
              Icon(Icons.check_rounded, size: 18, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

/// A small downward-pointing triangle in [color], forming the bubble's tail.
class _PointerPainter extends CustomPainter {
  final Color color;
  const _PointerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    // Soft shadow so the tail matches the bubble's elevation.
    canvas.drawShadow(path, Colors.black.withAlpha(60), 3, false);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.color != color;
}
