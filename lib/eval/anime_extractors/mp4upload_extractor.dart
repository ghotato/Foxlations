// Ported from Mangayomi's mp4upload_extractor.dart (Apache-2.0). See NOTICE.
import 'package:js_packer/js_packer.dart';

import 'extractor_common.dart';

class Mp4uploadExtractor {
  static final RegExp qualityRegex = RegExp(r'\WHEIGHT=(\d+)');
  static const String referer = "https://mp4upload.com/";

  Future<List<Video>> videosFromUrl(
    String url,
    Map<String, String> headers, {
    String prefix = '',
    String suffix = '',
  }) async {
    final client = extractorClient();
    final newHeaders = Map<String, String>.from(headers)
      ..addAll({'referer': referer});
    try {
      final response = await client.get(Uri.parse(url), headers: newHeaders);
      String script = "";

      final scriptElementWithEval = xpathSelector(response.body)
          .queryXPath(
            '//script[contains(text(), "eval") and contains(text(), "p,a,c,k,e,d")]/text()',
          )
          .attrs;

      if (scriptElementWithEval.isNotEmpty) {
        // Unpack the packed eval script (Mangayomi unpacked an empty string
        // here — clearly a slip; unpack the matched script instead).
        script = JSPacker(scriptElementWithEval.first ?? "").unpack() ?? "";
      } else {
        final scriptElementWithSrc = xpathSelector(
          response.body,
        ).queryXPath('//script[contains(text(), "player.src")]/text()').attrs;
        if (scriptElementWithSrc.isNotEmpty) {
          script = scriptElementWithSrc.first!;
        } else {
          return [];
        }
      }

      final videoUrl = script
          .substringAfter('.src(')
          .substringBefore(')')
          .substringAfter('src:')
          .substringAfter('"')
          .substringBefore('"');
      final resolutionMatch = qualityRegex.firstMatch(script);
      final resolution = resolutionMatch?.group(1) ?? 'Unknown resolution';
      final quality = '$prefix Mp4Upload - ${resolution}p $suffix';

      return [Video(videoUrl, quality, videoUrl, headers: newHeaders)];
    } catch (_) {
      return [];
    }
  }
}
