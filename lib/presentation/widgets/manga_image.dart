import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/services/image_loader.dart';

/// Image widget that loads images through our Cloudflare-aware HTTP pipeline.
class MangaImage extends StatefulWidget {
  final String imageUrl;
  final String? referer;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Uint8List? translatedBytes;

  const MangaImage({
    super.key,
    required this.imageUrl,
    this.referer,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.translatedBytes,
  });

  @override
  State<MangaImage> createState() => _MangaImageState();
}

class _MangaImageState extends State<MangaImage>
    with AutomaticKeepAliveClientMixin {
  Uint8List? _bytes;
  bool _loading = true;
  bool _error = false;

  // Keep alive so ListView doesn't destroy/rebuild during scroll
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(MangaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.imageUrl.isEmpty) {
      if (mounted) setState(() { _loading = false; _error = true; });
      return;
    }

    // Handle local file:// URLs
    if (widget.imageUrl.startsWith('file://')) {
      try {
        final path = widget.imageUrl.replaceFirst('file://', '');
        final bytes = await File(path).readAsBytes();
        if (mounted) setState(() { _bytes = bytes; _loading = false; _error = false; });
      } catch (_) {
        if (mounted) setState(() { _loading = false; _error = true; });
      }
      return;
    }

    // Don't reset to loading if we already have bytes (prevents flicker)
    if (_bytes == null) {
      if (mounted) setState(() { _loading = true; _error = false; });
    }

    // Build referer: if explicitly provided, use as-is (source knows best).
    // If falling back to imageUrl, add www. — many CDNs require it.
    var referer = widget.referer ?? widget.imageUrl;
    if (widget.referer == null) {
      final uri = Uri.tryParse(referer);
      if (uri != null && !uri.host.startsWith('www.')) {
        referer = referer.replaceFirst('://${uri.host}', '://www.${uri.host}');
      }
    }
    if (!referer.endsWith('/')) referer = '$referer/';

    final bytes = await ImageLoader().loadImage(
      widget.imageUrl,
      headers: {'Referer': referer},
    );

    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
      _error = bytes == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin

    if (_loading) {
      return widget.placeholder ?? _defaultPlaceholder(context);
    }
    if (_error || _bytes == null) {
      return widget.errorWidget ?? _defaultError(context);
    }
    final displayBytes = widget.translatedBytes ?? _bytes!;
    return Image.memory(
      displayBytes,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true, // Prevents flicker during rebuild
      errorBuilder: (_, __, ___) =>
          widget.errorWidget ?? _defaultError(context),
    );
  }

  Widget _defaultPlaceholder(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _defaultError(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Opacity(
          opacity: 0.25,
          child: Image.asset('assets/images/foxlations.png', width: 48, height: 48),
        ),
      ),
    );
  }
}
