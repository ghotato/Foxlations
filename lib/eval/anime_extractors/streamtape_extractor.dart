// Ported from Mangayomi's streamtape_extractor.dart (Apache-2.0). See NOTICE.
import 'package:html/parser.dart' show parse;

import 'extractor_common.dart';

class StreamTapeExtractor {
  Future<List<Video>> videosFromUrl(
    String url, {
    String quality = "StreamTape",
  }) async {
    final client = extractorClient();
    try {
      const baseUrl = "https://streamtape.com/e/";
      final newUrl = !url.startsWith(baseUrl)
          ? "$baseUrl${url.split("/")[4]}"
          : url;

      final response = await client.get(Uri.parse(newUrl));
      final document = parse(response.body);

      const targetLine = "document.getElementById('robotlink')";
      final scri = document
          .querySelectorAll("script")
          .where((element) => element.innerHtml.contains(targetLine))
          .map((e) => e.innerHtml)
          .toList();
      if (scri.isEmpty) {
        return [];
      }
      final script = scri.first.split("$targetLine.innerHTML = '").last;
      final videoUrl =
          "https:${script.substringBefore("'")}${script.substringAfter("+ ('xcd").substringBefore("'")}";

      return [Video(videoUrl, quality, videoUrl)];
    } catch (_) {
      return [];
    }
  }
}
