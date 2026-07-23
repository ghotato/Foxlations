// Shared plumbing for the anime video-host extractors.
//
// The extractors themselves are faithful Dart ports of Mangayomi's
// `lib/services/anime_extractors/*` (Apache-2.0). See NOTICE. Mangayomi's
// `Video`/`Track` map 1:1 onto Foxlations' [MVideo]/[MTrack], its `MClient`
// onto a plain `package:http` client (which follows redirects and exposes the
// final URL via `response.request.url`, as some hosts need), and its
// `string_extensions` onto the helpers below.
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import '../model/m_video.dart';

/// Mangayomi's extractors return `Video`/`Track`; Foxlations' equivalents are
/// identical in shape, so alias them and keep the ported code verbatim.
typedef Video = MVideo;
typedef Track = MTrack;

/// One shared client for every extractor. `package:http`'s client follows
/// redirects and keeps `response.request.url` pointing at the final URL, which
/// a few hosts (Doodstream, Streamlare) rely on.
http.Client extractorClient() => http.Client();

/// The directory portion of a URL path — a tiny stand-in for `path.dirname`,
/// used when a host gives m3u8 segment names relative to the playlist.
String urlDirname(String p) {
  final i = p.lastIndexOf('/');
  return i <= 0 ? '' : p.substring(0, i);
}

/// XPath over an HTML string — Mangayomi's `xpathSelector` helper, used by the
/// extractors that pull data out of inline `<script>` text. Returns an
/// [HtmlXPath] whose `queryXPath(expr).attrs` yields the matched values.
HtmlXPath xpathSelector(String html) {
  final root = parse(html).documentElement!;
  return HtmlXPath.node(root);
}

/// Kotlin-style scope function used by a couple of the ported extractors.
extension ObjectLet<T> on T {
  R let<R>(R Function(T it) op) => op(this);
}

/// The substring helpers Mangayomi sources and extractors lean on. Ported from
/// Mangayomi's `utils/extensions/string_extensions.dart` (Apache-2.0).
extension ExtractorStringExtensions on String {
  String substringAfter(String pattern) {
    final startIndex = indexOf(pattern);
    if (startIndex == -1) return substring(0);
    return substring(startIndex + pattern.length);
  }

  String substringAfterLast(String pattern) => split(pattern).last;

  String substringBefore(String pattern) {
    final endIndex = indexOf(pattern);
    if (endIndex == -1) return substring(0);
    return substring(0, endIndex);
  }

  String substringBeforeLast(String pattern) {
    final endIndex = lastIndexOf(pattern);
    if (endIndex == -1) return substring(0);
    return substring(0, endIndex);
  }

  String substringBetween(String left, String right) {
    final index = indexOf(left);
    if (index == -1) return '';
    final leftIndex = index + left.length;
    final rightIndex = indexOf(right, leftIndex);
    if (rightIndex == -1) return '';
    return substring(leftIndex, rightIndex);
  }
}
