import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class AppNavigation extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isVaultMode;
  final int updatesBadge;

  const AppNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isVaultMode = false,
    this.updatesBadge = 0,
  });

  @override
  State<AppNavigation> createState() => _AppNavigationState();
}

class _AppNavigationState extends State<AppNavigation>
    with SingleTickerProviderStateMixin {
  late AnimationController _snakeController;
  late Animation<double> _snakeAnimation;
  int _previousIndex = 0;

  static const List<_NavItem> _items = [
    _NavItem(
      icon: Icons.collections_bookmark_outlined,
      activeIcon: Icons.collections_bookmark,
      label: 'Library',
    ),
    _NavItem(
      icon: Icons.update_outlined,
      activeIcon: Icons.update,
      label: 'Updates',
    ),
    _NavItem(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore,
      label: 'Browse',
    ),
    _NavItem(
      icon: Icons.more_horiz_rounded,
      activeIcon: Icons.more_horiz,
      label: 'More',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _snakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _snakeAnimation = CurvedAnimation(
      parent: _snakeController,
      curve: Curves.easeOutCubic,
    );
    _previousIndex = widget.currentIndex;
  }

  @override
  void didUpdateWidget(AppNavigation old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _previousIndex = old.currentIndex;
      _snakeController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _snakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final tabWidth = width / _items.length;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(77),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 4),
        child: SizedBox(
          height: 64,
          child: Stack(
            children: [
              // Snake indicator
              AnimatedBuilder(
                animation: _snakeAnimation,
                builder: (_, __) {
                  final fromX = _previousIndex * tabWidth + tabWidth / 2 - 32;
                  final toX =
                      widget.currentIndex * tabWidth + tabWidth / 2 - 32;
                  final currentX =
                      fromX + (toX - fromX) * _snakeAnimation.value;
                  return Positioned(
                    left: currentX,
                    top: 4,
                    child: Container(
                      width: 64,
                      height: 52,
                      decoration: BoxDecoration(
                        color: cs.primary.withAlpha(26),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  );
                },
              ),
              // Tab buttons
              Row(
                children: List.generate(_items.length, (index) {
                  final item = _items[index];
                  final isActive = widget.currentIndex == index;
                  // Swap Library icon/label when in vault mode
                  final IconData icon;
                  final IconData activeIcon;
                  final String label;
                  if (index == 0 && widget.isVaultMode) {
                    icon = Icons.shield_outlined;
                    activeIcon = Icons.shield_rounded;
                    label = 'Vault';
                  } else {
                    icon = item.icon;
                    activeIcon = item.activeIcon;
                    label = item.label;
                  }
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => widget.onTap(index),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedSwitcher(
                                duration: AppTheme.fastMicro,
                                child: Icon(
                                  isActive ? activeIcon : icon,
                                  key: ValueKey('${isActive}_${widget.isVaultMode}'),
                                  size: 22,
                                  color: isActive ? cs.primary : cs.outline,
                                ),
                              ),
                              if (index == 1 && widget.updatesBadge > 0)
                                Positioned(right: -6, top: -4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      borderRadius: BorderRadius.circular(8)),
                                    child: Text(
                                      widget.updatesBadge > 99 ? '99+' : '${widget.updatesBadge}',
                                      style: GoogleFonts.manrope(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white)),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            label,
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isActive ? cs.primary : cs.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
