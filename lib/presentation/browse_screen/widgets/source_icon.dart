import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/source_model.dart';

/// A source's icon, degrading to its first letter.
///
/// Every browse list previously drew the letter tile unconditionally — the icon
/// was never rendered anywhere, even when the repo published one. The network
/// image still has to fail softly: repos move, hosts 403, and icons go missing,
/// and a broken-image box reads worse than the letter tile it replaced. So both
/// the error and the loading state fall back to that same tile, which also
/// keeps the row from reflowing once the image arrives.
class SourceIcon extends StatelessWidget {
  const SourceIcon({
    super.key,
    required this.source,
    this.size = 40,
    this.radius = 8,
    this.fontSize = 18,
  });

  final MangaSource source;
  final double size;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final letter = Center(
      child: Text(
        source.name.isNotEmpty ? source.name[0].toUpperCase() : '?',
        style: GoogleFonts.manrope(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: source.iconUrl.isEmpty
          ? letter
          : CachedNetworkImage(
              imageUrl: source.iconUrl,
              fit: BoxFit.cover,
              width: size,
              height: size,
              placeholder: (_, __) => letter,
              errorWidget: (_, __, ___) => letter,
            ),
    );
  }
}
