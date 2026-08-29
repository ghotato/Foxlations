// Ported from Mangayomi's okru_extractor.dart (Apache-2.0). See NOTICE.
// Mangayomi's dom_extensions `selectFirst`/`attr` become `querySelector`/
// `attributes`, and `path.dirname` becomes [urlDirname].
import 'package:html/parser.dart' show parse;

import 'extractor_common.dart';

class OkruExtractor {
  Future<List<Video>> videosFromUrl(
    String url, {
    String prefix = "",
    bool fixQualities = true,
  }) async {
    final client = extractorClient();
    final response = await client.get(Uri.parse(url));
    final document = parse(response.body);
    final videoString = document
        .querySelector('div[data-options]')
        ?.attributes["data-options"];

    if (videoString == null) {
      return [];
    }

    if (videoString.contains('ondemandHls')) {
      final playlistUrl = Uri.parse(
        videoString
            .substringAfter("ondemandHls\\\":\\\"")
            .substringBefore("\\\"")
            .replaceAll("\\\\u0026", "&"),
      );

      final masterPlaylistResponse = await client.get(playlistUrl);
      final masterPlaylist = masterPlaylistResponse.body;

      const separator = "#EXT-X-STREAM-INF";
      return masterPlaylist.substringAfter(separator).split(separator).map((
        it,
      ) {
        final resolution =
            "${it.substringAfter("RESOLUTION=").substringBefore("\n").substringAfter("x").substringBefore(",")}p";
        final m3u8Host =
            "${playlistUrl.scheme}://${playlistUrl.host}${urlDirname(playlistUrl.path)}";
        final videoUrl =
            "$m3u8Host/${it.substringAfter("\n").substringBefore("\n")}";
        return Video(
          videoUrl,
          "${prefix.isNotEmpty ? prefix : ""}Okru:$resolution",
          videoUrl,
        );
      }).toList();
    }

    return [];
  }
}
