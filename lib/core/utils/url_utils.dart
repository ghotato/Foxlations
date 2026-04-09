/// Safely extract origin from a URL.
/// Returns null for relative paths, malformed URLs, or URLs without a scheme.
String? safeOrigin(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return null;
  try {
    return uri.origin;
  } catch (_) {
    return null;
  }
}
