import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

/// A detected speech bubble with translation data. [bounds] is normalized
/// (0.0–1.0) relative to the source image.
class TranslationBubble {
  final String id;
  final Rect bounds;
  final String originalText;
  final String translatedText;
  final bool isTranslated;

  TranslationBubble({
    required this.id,
    required this.bounds,
    required this.originalText,
    this.translatedText = '',
    this.isTranslated = false,
  });
}

/// Draws translation bubbles over ONE page image.
///
/// It's placed as a `Positioned.fill` child of a Stack wrapping the image, so
/// its layout box matches the image's box. The bubbles' normalized bounds are
/// mapped into the *displayed* image rect — for webtoon (fit-width) that's the
/// whole box; for a letterboxed page (fit-contain) it's the centered contained
/// rect, computed from [imageSize]. This is what makes the boxes land on the
/// actual text instead of floating in the letterbox margins.
class ReaderTranslationOverlay extends StatelessWidget {
  final List<TranslationBubble> bubbles;
  final Animation<double> animation;
  /// Natural pixel size of the source image, for the fit-contain letterbox math.
  /// Null → assume the image fills the box.
  final Size? imageSize;
  /// True in webtoon/vertical mode (image fills the width; box == image).
  final bool fitWidth;
  /// Global translated-vs-original state; individual bubbles can still flip.
  final bool showTranslated;
  final bool useMangaFont;

  const ReaderTranslationOverlay({
    super.key,
    required this.bubbles,
    required this.animation,
    this.imageSize,
    this.fitWidth = false,
    this.showTranslated = true,
    this.useMangaFont = false,
  });

  Rect _displayedRect(Size box) {
    final img = imageSize;
    if (img == null || img.width <= 0 || img.height <= 0) {
      return Offset.zero & box;
    }
    final scale = fitWidth
        ? box.width / img.width
        : math.min(box.width / img.width, box.height / img.height);
    final w = img.width * scale;
    final h = img.height * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  @override
  Widget build(BuildContext context) {
    if (bubbles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (_, constraints) {
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final rect = _displayedRect(box);
        return Stack(
          children: bubbles.map((bubble) {
            final left = rect.left + bubble.bounds.left * rect.width;
            final top = rect.top + bubble.bounds.top * rect.height;
            final width = bubble.bounds.width * rect.width;
            final height = bubble.bounds.height * rect.height;
            return Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: FadeTransition(
                opacity: animation,
                child: _BubbleWidget(
                  bubble: bubble,
                  forceTranslated: showTranslated,
                  bubbleHeightPx: height,
                  useMangaFont: useMangaFont,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _BubbleWidget extends StatefulWidget {
  final TranslationBubble bubble;
  final bool forceTranslated;
  final double bubbleHeightPx;
  final bool useMangaFont;

  const _BubbleWidget({
    required this.bubble,
    required this.forceTranslated,
    required this.bubbleHeightPx,
    required this.useMangaFont,
  });

  @override
  State<_BubbleWidget> createState() => _BubbleWidgetState();
}

class _BubbleWidgetState extends State<_BubbleWidget> {
  bool _localFlipped = false;

  @override
  void didUpdateWidget(_BubbleWidget old) {
    super.didUpdateWidget(old);
    if (old.forceTranslated != widget.forceTranslated) _localFlipped = false;
  }

  @override
  Widget build(BuildContext context) {
    final showOriginal = widget.forceTranslated ? _localFlipped : !_localFlipped;
    final text = showOriginal ? widget.bubble.originalText : widget.bubble.translatedText;

    final fontSize = (widget.bubbleHeightPx * 0.14).clamp(8.0, 20.0);

    final baseStyle = widget.useMangaFont
        ? GoogleFonts.bangers(
            fontSize: fontSize,
            fontWeight: FontWeight.w400,
            color: showOriginal ? Colors.white : Colors.black87,
            height: 1.2,
            letterSpacing: 0.5,
          )
        : GoogleFonts.manrope(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: showOriginal ? Colors.white : Colors.black87,
            height: 1.3,
          );

    return GestureDetector(
      onTap: () => setState(() => _localFlipped = !_localFlipped),
      child: AnimatedContainer(
        duration: AppTheme.fastMicro,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: showOriginal ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: showOriginal ? AppTheme.secondary.withAlpha(153) : Colors.transparent,
            width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(102), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: _StrokedText(
              key: ValueKey(showOriginal),
              text: text,
              style: baseStyle,
              showOriginal: showOriginal,
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders text with a subtle stroke underneath for readability.
class _StrokedText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool showOriginal;

  const _StrokedText({
    super.key,
    required this.text,
    required this.style,
    required this.showOriginal,
  });

  @override
  Widget build(BuildContext context) {
    final strokeColor = showOriginal ? Colors.white.withAlpha(100) : Colors.black.withAlpha(60);
    final strokeStyle = TextStyle(
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      height: style.height,
      letterSpacing: style.letterSpacing,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = strokeColor,
    );
    return Stack(
      children: [
        Text(text, textAlign: TextAlign.center, maxLines: 6, style: strokeStyle),
        Text(text, textAlign: TextAlign.center, maxLines: 6, style: style),
      ],
    );
  }
}
