import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBlur;
  final double elevation;

  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.showBlur = true,
    this.elevation = 0,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.of(context).padding.top;

    return ClipRRect(
      child: BackdropFilter(
        filter: showBlur
            ? ImageFilter.blur(sigmaX: 20, sigmaY: 20)
            : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: Container(
          height: kToolbarHeight + topPadding,
          padding: EdgeInsets.only(top: topPadding),
          decoration: BoxDecoration(
            color: showBlur
                ? cs.surface.withAlpha(0xB3)
                : cs.surface,
            border: showBlur
                ? const Border(
                    bottom: BorderSide(
                      color: Color(0x1AFFFFFF),
                      width: 1,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              if (leading != null)
                leading!
              else
                const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (actions != null) ...actions!,
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
