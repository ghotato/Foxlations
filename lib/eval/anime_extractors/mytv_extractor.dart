// Ported from Mangayomi's mytv_extractor.dart (Apache-2.0). See NOTICE.
import 'package:html/parser.dart' show parse;

import 'extractor_common.dart';

class MytvExtractor {
  Future<List<Video>> videosFromUrl(String url) async {
    final client = extractorClient();
    try {
      final response = await client.get(Uri.parse(url));
      final document = parse(response.body);
      final videoList = <Video>[];

      for (final script in document.querySelectorAll("script")) {
        if (script.text.contains("CreatePlayer(\"v")) {
          final videosString = script.text;
          final videoUrl = videosString
              .substringAfter("\"v=")
              .substringBefore("\\u0026tp=video")
              .replaceAll("%26", "&")
              .replaceAll("%3a", ":")
              .replaceAll("%2f", "/")
              .replaceAll("%3f", "?")
              .replaceAll("%3d", "=");

          if (!videoUrl.contains("https:")) {
            videoList.add(Video(videoUrl, "Stream", videoUrl));
          } else {
            videoList.add(Video(videoUrl, "Mytv", videoUrl));
          }
        }
      }

      return videoList;
    } catch (_) {
      return [];
    }
  }
}
