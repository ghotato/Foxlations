// Ported from Mangayomi's vidbom_extractor.dart (Apache-2.0). See NOTICE.
import 'extractor_common.dart';

class VidBomExtractor {
  Future<List<Video>> videosFromUrl(String url) async {
    final client = extractorClient();
    try {
      final response = await client.get(Uri.parse(url));
      final script = xpathSelector(
        response.body,
      ).queryXPath('//script[contains(text(), "sources")]/text()').attrs;

      final data = script.first!
          .substringAfter('sources: [')
          .substringBefore('],');

      return data.split('file:"').skip(1).map((source) {
        final src = source.substringBefore('"');
        var quality =
            'Vidbom - ${source.substringAfter('label:"').substringBefore('"')}';
        if (quality.length > 15) {
          quality = 'Vidshare - 480p';
        }
        return Video(src, quality, src);
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
