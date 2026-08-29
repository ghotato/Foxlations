import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

enum _ImageType { network, file, asset }

extension _ImageTypeDetection on String {
  _ImageType get imageType {
    if (startsWith('http://') || startsWith('https://')) return _ImageType.network;
    if (startsWith('file://') || startsWith('/')) return _ImageType.file;
    return _ImageType.asset;
  }
}

class CustomImageWidget extends StatelessWidget {
  final String? imageUrl;
  final double? height;
  final double? width;
  final BoxFit? fit;
  final Color? color;
  final Alignment? alignment;
  final VoidCallback? onTap;
  final BorderRadius? radius;
  final EdgeInsetsGeometry? margin;
  final BoxBorder? border;
  final Widget? errorWidget;
  final String? semanticLabel;
  final Map<String, String>? headers;

  const CustomImageWidget({
    super.key,
    this.imageUrl,
    this.height,
    this.width,
    this.fit,
    this.color,
    this.alignment,
    this.onTap,
    this.radius,
    this.margin,
    this.border,
    this.errorWidget,
    this.semanticLabel,
    this.headers,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget image;
    if (imageUrl == null || imageUrl!.isEmpty) {
      image = _buildPlaceholder(cs);
    } else {
      final type = imageUrl!.imageType;
      switch (type) {
        case _ImageType.network:
          image = CachedNetworkImage(
            imageUrl: imageUrl!,
            height: height,
            width: width,
            fit: fit ?? BoxFit.cover,
            color: color,
            httpHeaders: headers,
            placeholder: (_, _) => Container(
              height: height,
              width: width,
              color: cs.surfaceContainerHighest,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
            errorWidget: (_, _, _) =>
                errorWidget ?? _buildErrorWidget(cs),
          );
          break;
        case _ImageType.file:
          final path = imageUrl!.startsWith('file://')
              ? Uri.parse(imageUrl!).toFilePath()
              : imageUrl!;
          image = Image.file(
            File(path),
            height: height,
            width: width,
            fit: fit ?? BoxFit.cover,
            color: color,
            semanticLabel: semanticLabel,
            errorBuilder: (_, _, _) =>
                errorWidget ?? _buildErrorWidget(cs),
          );
          break;
        case _ImageType.asset:
          image = Image.asset(
            imageUrl!,
            height: height,
            width: width,
            fit: fit ?? BoxFit.cover,
            color: color,
            semanticLabel: semanticLabel,
            errorBuilder: (_, _, _) =>
                errorWidget ?? _buildErrorWidget(cs),
          );
          break;
      }
    }

    // Apply clipping
    if (radius != null) {
      image = ClipRRect(borderRadius: radius!, child: image);
    }

    // Apply border
    if (border != null) {
      image = Container(
        decoration: BoxDecoration(border: border, borderRadius: radius),
        child: image,
      );
    }

    // Apply margin
    if (margin != null) {
      image = Padding(padding: margin!, child: image);
    }

    // Apply tap
    if (onTap != null) {
      image = GestureDetector(onTap: onTap, child: image);
    }

    // Apply alignment
    if (alignment != null) {
      image = Align(alignment: alignment!, child: image);
    }

    return image;
  }

  Widget _buildPlaceholder(ColorScheme cs) {
    return Container(
      height: height,
      width: width,
      color: cs.surfaceContainerHighest,
      child: Icon(
        Icons.image_rounded,
        color: cs.outline,
        size: 28,
      ),
    );
  }

  Widget _buildErrorWidget(ColorScheme cs) {
    return Container(
      height: height,
      width: width,
      color: cs.surfaceContainerHighest,
      child: Icon(
        Icons.broken_image_rounded,
        color: cs.outline,
        size: 28,
      ),
    );
  }
}
