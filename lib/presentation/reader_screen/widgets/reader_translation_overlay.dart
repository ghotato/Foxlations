import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../theme/app_theme.dart';

/// A detected speech bubble with translation data.
class TranslationBubble {
  final String id;
  final Rect bounds; // Relative position (0.0-1.0) on page
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

/// Overlay widget that displays translation bubbles on manga pages.
class ReaderTranslationOverlay extends StatefulWidget {
  final List<TranslationBubble> bubbles;
  final Animation<double> animation;
  final bool isTranslating;

  const ReaderTranslationOverlay({
    super.key,
    required this.bubbles,
    required this.animation,
    required this.isTranslating,
  });

  @override
  State<ReaderTranslationOverlay> createState() => _ReaderTranslationOverlayState();
}

class _ReaderTranslationOverlayState extends State<ReaderTranslationOverlay> {
  bool _showAllTranslated = true;
  bool _useMangaFont = false;

  @override
  void initState() {
    super.initState();
    _loadFontPref();
  }

  Future<void> _loadFontPref() async {
    final prefs = await SharedPreferences.getInstance();
    final font = prefs.getString('translation_font') ?? 'manrope';
    if (mounted) setState(() => _useMangaFont = font == 'bangers');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isTranslating) {
      return Positioned.fill(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(179),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white70))),
              const SizedBox(width: 10),
              Text('Detecting speech bubbles...',
                  style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            ]),
          ),
        ),
      );
    }

    if (widget.bubbles.isEmpty) return const SizedBox.shrink();

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (_, constraints) {
          return Stack(
            children: [
              // Bubble overlays
              ...widget.bubbles.map((bubble) {
                final left = bubble.bounds.left * constraints.maxWidth;
                final top = bubble.bounds.top * constraints.maxHeight;
                final width = bubble.bounds.width * constraints.maxWidth;
                final height = bubble.bounds.height * constraints.maxHeight;

                return Positioned(
                  left: left, top: top, width: width, height: height,
                  child: FadeTransition(
                    opacity: widget.animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.85, end: 1.0).animate(widget.animation),
                      child: _BubbleWidget(
                        bubble: bubble,
                        forceTranslated: _showAllTranslated,
                        bubbleHeightPx: height,
                        useMangaFont: _useMangaFont,
                      ),
                    ),
                  ),
                );
              }),

              // Toggle button — bottom-right corner
              Positioned(
                right: 8,
                bottom: 8,
                child: FadeTransition(
                  opacity: widget.animation,
                  child: GestureDetector(
                    onTap: () => setState(() => _showAllTranslated = !_showAllTranslated),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(179),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          _showAllTranslated ? Icons.translate_rounded : Icons.text_fields_rounded,
                          color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          _showAllTranslated ? 'Translated' : 'Original',
                          style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
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
  // Whether the user has locally flipped this bubble from the global state.
  bool _localFlipped = false;

  @override
  void didUpdateWidget(_BubbleWidget old) {
    super.didUpdateWidget(old);
    // Reset local flip whenever the global toggle changes.
    if (old.forceTranslated != widget.forceTranslated) _localFlipped = false;
  }

  @override
  Widget build(BuildContext context) {
    // forceTranslated=true → default shows translated; tap flips to original
    // forceTranslated=false → default shows original; tap flips to translated
    final showOriginal = widget.forceTranslated ? _localFlipped : !_localFlipped;
    final text = showOriginal ? widget.bubble.originalText : widget.bubble.translatedText;

    // Scale font to bubble height. Raised cap to 20 so larger bubbles fill well;
    // FittedBox.contain scales down if text overflows.
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
          // Fully opaque so original manga text doesn't bleed through.
          color: showOriginal ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: showOriginal ? AppTheme.secondary.withAlpha(153) : Colors.transparent,
            width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(102), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: AppTheme.fastMicro,
            child: FittedBox(
              // contain scales both up AND down — fills large bubbles, shrinks on overflow
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
      ),
    );
  }
}

/// Renders text with a subtle stroke underneath for readability (2-pass like koharu/TachiyomiAT).
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
    // Stroke color: contrasting halo behind the fill color
    final strokeColor = showOriginal ? Colors.white.withAlpha(100) : Colors.black.withAlpha(60);

    // foreground and color are mutually exclusive in TextStyle — build stroke style without color
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
