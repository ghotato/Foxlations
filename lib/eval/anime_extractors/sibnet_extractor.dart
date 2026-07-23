// Ported from Mangayomi's sibnet_extractor.dart (Apache-2.0). See NOTICE.
import 'extractor_common.dart';

class SibnetExtractor {
  Future<List<Video>> videosFromUrl(String url, {String prefix = ""}) async {
    final client = extractorClient();
    final List<Video> videoList = [];
    try {
      final response = await client.get(Uri.parse(url));
      if (response.statusCode != 200) {
        return [];
      }

      final String script = response.body;
      final String slug = script
          .substringAfter("player.src")
          .substringAfter("src:")
          .substringAfter("\"")
          .substringBefore("\"");

      final String videoUrl = slug.contains("http")
          ? slug
          : "https://${Uri.parse(url).host}$slug";

      final Map<String, String> videoHeaders = {"Referer": url};

      videoList.add(
        Video(videoUrl, "$prefix - Sibnet", videoUrl, headers: videoHeaders),
      );

      return videoList;
    } catch (_) {
      return [];
    }
  }
}
