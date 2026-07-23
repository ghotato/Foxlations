import 'dart:convert';

import 'package:d4rt/d4rt.dart';

import '../../anime_extractors/dood_extractor.dart';
import '../../anime_extractors/filemoon_extractor.dart';
import '../../anime_extractors/gogocdn_extractor.dart';
import '../../anime_extractors/mp4upload_extractor.dart';
import '../../anime_extractors/mytv_extractor.dart';
import '../../anime_extractors/okru_extractor.dart';
import '../../anime_extractors/sendvid_extractor.dart';
import '../../anime_extractors/sibnet_extractor.dart';
import '../../anime_extractors/streamlare_extractor.dart';
import '../../anime_extractors/streamtape_extractor.dart';
import '../../anime_extractors/streamwish_extractor.dart';
import '../../anime_extractors/vidbom_extractor.dart';
import '../../anime_extractors/voe_extractor.dart';
import '../../anime_extractors/your_upload_extractor.dart';

/// Registers the anime video-host extractors as top-level functions callable
/// from interpreted (d4rt) sources — the Mangayomi/m2k3a-format anime sources
/// call these by name from their `getVideoList`.
///
/// The extractor implementations under `lib/eval/anime_extractors/` are Dart
/// ports of Mangayomi's (Apache-2.0); this file mirrors the way Mangayomi's
/// own bridge exposes them (`doodExtractor`, `streamTapeExtractor`, …). See
/// NOTICE.
class ExtractorBridge {
  static Map<String, String> _decodeHeaders(Object? headers) {
    if (headers == null) return {};
    if (headers is Map) {
      return headers.map((k, v) => MapEntry('$k', '$v'));
    }
    try {
      final decoded = jsonDecode('$headers');
      if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {}
    return {};
  }

  static String? _optStr(List<Object?> args, int i) =>
      args.length > i ? args[i] as String? : null;

  static void register(D4rt interpreter, String lib) {
    interpreter.registertopLevelFunction(
      'doodExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          DoodExtractor().videosFromUrl(
        positionalArgs[0] as String,
        quality: _optStr(positionalArgs, 1),
      ),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'streamTapeExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          StreamTapeExtractor().videosFromUrl(
        positionalArgs[0] as String,
        quality: _optStr(positionalArgs, 1) ?? 'StreamTape',
      ),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'sibnetExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          SibnetExtractor().videosFromUrl(
        positionalArgs[0] as String,
        prefix: _optStr(positionalArgs, 1) ?? '',
      ),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'okruExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          OkruExtractor().videosFromUrl(positionalArgs[0] as String),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'myTvExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          MytvExtractor().videosFromUrl(positionalArgs[0] as String),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'sendVidExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) => SendvidExtractor(
        _decodeHeaders(_optStr(positionalArgs, 1)),
      ).videosFromUrl(
        positionalArgs[0] as String,
        prefix: _optStr(positionalArgs, 2) ?? '',
      ),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'streamlareExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          StreamlareExtractor().videosFromUrl(
        positionalArgs[0] as String,
        prefix: _optStr(positionalArgs, 1) ?? '',
        suffix: _optStr(positionalArgs, 2) ?? '',
      ),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'vidBomExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          VidBomExtractor().videosFromUrl(positionalArgs[0] as String),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'yourUploadExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          YourUploadExtractor().videosFromUrl(
        positionalArgs[0] as String,
        _decodeHeaders(_optStr(positionalArgs, 1)),
        name: _optStr(positionalArgs, 2) ?? 'YourUpload',
        prefix: _optStr(positionalArgs, 3) ?? '',
      ),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'mp4UploadExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          Mp4uploadExtractor().videosFromUrl(
        positionalArgs[0] as String,
        _decodeHeaders(_optStr(positionalArgs, 1)),
        prefix: _optStr(positionalArgs, 2) ?? '',
        suffix: _optStr(positionalArgs, 3) ?? '',
      ),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'streamWishExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          StreamWishExtractor().videosFromUrl(
        positionalArgs[0] as String,
        _optStr(positionalArgs, 1) ?? '',
      ),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'filemoonExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          FilemoonExtractor().videosFromUrl(
        positionalArgs[0] as String,
        _optStr(positionalArgs, 1) ?? '',
        _optStr(positionalArgs, 2) ?? '',
      ),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'gogoCdnExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          GogoCdnExtractor().videosFromUrl(positionalArgs[0] as String),
      sourceUri: lib,
    );

    interpreter.registertopLevelFunction(
      'voeExtractor',
      (visitor, positionalArgs, namedArgs, typeArgs) =>
          VoeExtractor().videosFromUrl(
        positionalArgs[0] as String,
        _optStr(positionalArgs, 1),
      ),
      sourceUri: lib,
    );
  }
}
