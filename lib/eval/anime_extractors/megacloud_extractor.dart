// MegaCloud / RapidCloud extractor — the host behind HiAnime (Zorotheme) and
// the FlixHQ family. Ported from yuzono's MegaCloudExtractor (Apache-2.0). See
// NOTICE.
//
// No decryption is reimplemented: get a nonce from the embed page, fetch the
// sources JSON, and when they're encrypted, pull the community `mega` key and
// hand the payload to the enc-dec.app decryptor, which returns the m3u8. This
// mirrors what the upstream extractor does; if that key feed or decryptor
// service goes down, encrypted sources are skipped rather than crashing.
import 'dart:convert';

import 'extractor_common.dart';

class MegaCloudExtractor {
  static const _sourcesUrl = '/embed-2/v3/e-1/getSources?id=';
  static const _splitter = '/e-1/';
  static const _decApi = 'https://enc-dec.app/api/dec-mega';
  static const _keysUrl =
      'https://raw.githubusercontent.com/yogesh-hacker/MegacloudKeys/refs/heads/main/keys.json';

  Future<List<Video>> videosFromUrl(String url, [String name = 'MegaCloud']) async {
    final client = extractorClient();
    try {
      final host = Uri.parse(url).host;
      if (host.isEmpty) return [];
      final server = 'https://$host';
      final id = url.substringAfter(_splitter).substringBefore('?');
      if (id.isEmpty) return [];

      final hdr = {
        'Accept': '*/*',
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': '$server/',
      };

      // The page carries a per-request nonce: either one 48-char token or three
      // 16-char tokens concatenated.
      final pageBody = (await client.get(Uri.parse(url), headers: hdr)).body;
      var nonce = RegExp(r'\b[a-zA-Z0-9]{48}\b').firstMatch(pageBody)?.group(0) ?? '';
      if (nonce.isEmpty) {
        final m = RegExp(
                r'\b([a-zA-Z0-9]{16})\b.*?\b([a-zA-Z0-9]{16})\b.*?\b([a-zA-Z0-9]{16})\b')
            .firstMatch(pageBody);
        if (m != null) nonce = '${m.group(1)}${m.group(2)}${m.group(3)}';
      }
      if (nonce.isEmpty) return [];

      final srcRes =
          await client.get(Uri.parse('$server$_sourcesUrl$id&_k=$nonce'), headers: hdr);
      final data = jsonDecode(srcRes.body);
      if (data is! Map) return [];
      final encrypted = data['encrypted'] != false;

      final subs = <Track>[];
      final tracks = data['tracks'];
      if (tracks is List) {
        for (final t in tracks) {
          if (t is Map && t['kind'] == 'captions') {
            subs.add(Track(file: t['file']?.toString(), label: t['label']?.toString()));
          }
        }
      }

      final videos = <Video>[];
      final sources = data['sources'];
      if (sources is List) {
        for (final s in sources) {
          if (s is! Map) continue;
          var m3u8 = s['file']?.toString() ?? '';
          if (encrypted && !m3u8.contains('.m3u8')) {
            final key = await _key(client);
            if (key.isEmpty) continue;
            final decUrl = '$_decApi'
                '?encrypted_data=${Uri.encodeComponent(m3u8)}'
                '&nonce=${Uri.encodeComponent(nonce)}'
                '&secret=${Uri.encodeComponent(key)}';
            final decBody = (await client.get(Uri.parse(decUrl))).body;
            m3u8 = RegExp(r'"file":"(.*?)"')
                    .firstMatch(decBody)
                    ?.group(1)
                    ?.replaceAll(r'\/', '/') ??
                '';
          }
          if (m3u8.isEmpty) continue;
          videos.add(Video(
            m3u8,
            name,
            m3u8,
            headers: {'Referer': '$server/'},
            subtitles: subs.isEmpty ? null : subs,
          ));
        }
      }
      return videos;
    } catch (_) {
      return [];
    }
  }

  Future<String> _key(dynamic client) async {
    try {
      final res = await client.get(Uri.parse(_keysUrl));
      final j = jsonDecode(res.body);
      return (j is Map ? j['mega'] : null)?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }
}
