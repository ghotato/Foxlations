import '../../eval/model/m_manga.dart';

/// Keep only search results whose title actually matches [query].
///
/// Many source `search()` implementations silently fall back to a popular /
/// browse listing when the site ignores the query parameter (e.g. Next.js
/// static browse endpoints, or APIs that only honor a `sort`). Without this the
/// UI shows unrelated "popular" titles as if they were search hits.
///
/// A result matches if its title contains the whole query, or contains every
/// (2+ char) query word. Case-insensitive. Empty query → returned unchanged.
List<MManga> filterSearchResults(List<MManga> list, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty || list.isEmpty) return list;
  final words = q.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
  return list.where((m) {
    final n = (m.name ?? '').toLowerCase();
    if (n.isEmpty) return false;
    if (n.contains(q)) return true;
    return words.isNotEmpty && words.every((w) => n.contains(w));
  }).toList();
}
