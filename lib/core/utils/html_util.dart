/// Strip HTML tags/entities from source-provided text (e.g. manga descriptions
/// that some APIs return as raw `<p class="…">…</p>` markup). Block tags become
/// line breaks; common entities are decoded; whitespace is tidied.
String stripHtml(String input) {
  if (input.isEmpty || !input.contains('<') && !input.contains('&')) {
    return input.trim();
  }
  var s = input;
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
