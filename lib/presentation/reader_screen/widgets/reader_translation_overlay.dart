import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
class ReaderTranslationOverlay extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (isTranslating) {
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

    if (bubbles.isEmpty) return const SizedBox.shrink();

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (_, constraints) {
          return Stack(
            children: bubbles.map((bubble) {
              final left = bubble.bounds.left * constraints.maxWidth;
              final top = bubble.bounds.top * constraints.maxHeight;
              final width = bubble.bounds.width * constraints.maxWidth;
              final height = bubble.bounds.height * constraints.maxHeight;

              return Positioned(
                left: left, top: top, width: width, height: height,
                child: FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.85, end: 1.0).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
                    child: _BubbleWidget(bubble: bubble),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _BubbleWidget extends StatefulWidget {
  final TranslationBubble bubble;
  const _BubbleWidget({required this.bubble});

  @override
  State<_BubbleWidget> createState() => _BubbleWidgetState();
}

class _BubbleWidgetState extends State<_BubbleWidget> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _showOriginal = !_showOriginal),
      child: AnimatedContainer(
        duration: AppTheme.fastMicro,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: _showOriginal ? Colors.black.withAlpha(209) : Colors.white.withAlpha(235),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: _showOriginal ? AppTheme.secondary.withAlpha(153) : Colors.transparent, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(102), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: AppTheme.fastMicro,
            child: Text(
              _showOriginal ? widget.bubble.originalText : widget.bubble.translatedText,
              key: ValueKey(_showOriginal),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: _showOriginal ? Colors.white : Colors.black87, height: 1.3),
            ),
          ),
        ),
      ),
    );
  }
}
