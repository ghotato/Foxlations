/// Strip HTML tags/entities from source-provided text (e.g. manga descriptions
/// that some APIs return as raw `<p class="…">…</p>` markup). Block tags become
/// line breaks; common entities are decoded; whitespace is tidied.
String stripHtml(String input) {
  var s = input;
  // Some sources double-encode markup as JSON escapes, so the description
  // arrives as the literal text `<p>…</p>` (and `\/`, `\"`).
  // Decode those first, otherwise the tag/entity handling below never sees a
  // real `<`, `>` or `&` and the escapes render verbatim on the detail screen.
  if (s.contains(r'\u') || s.contains(r'\/')) {
    s = s.replaceAllMapped(
      RegExp(r'\\u([0-9a-fA-F]{4})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
    s = s.replaceAll(r'\/', '/').replaceAll(r'\"', '"');
  }
  // Numeric HTML entities (&#233; / &#xE9;) that the named table below misses.
  if (s.contains('&#')) {
    s = s.replaceAllMapped(
      RegExp(r'&#(x?[0-9a-fA-F]+);'),
      (m) {
        final g = m.group(1)!;
        final code = g.startsWith('x')
            ? int.tryParse(g.substring(1), radix: 16)
            : int.tryParse(g);
        return code != null ? String.fromCharCode(code) : m.group(0)!;
      },
    );
  }
  if (s.isEmpty || (!s.contains('<') && !s.contains('&'))) {
    return s.trim();
  }
  s = s.replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(
      RegExp(r'</\s*(p|div|li|h[1-6]|blockquote)\s*>', caseSensitive: false),
      '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&hellip;', '…')
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–');
  s = s
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}
