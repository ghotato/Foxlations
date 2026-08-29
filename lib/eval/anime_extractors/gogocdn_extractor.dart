// Ported from Mangayomi's gogocdn_extractor.dart (Apache-2.0). See NOTICE.
// Mangayomi's `MBridge.cryptoHandler` (CryptoJS-style AES-CBC over raw
// key/iv strings) is inlined here as [_cryptoHandler].
import 'dart:convert';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import 'extractor_common.dart';

String _cryptoHandler(
  String text,
  String iv,
  String secretKeyString,
  bool doEncrypt,
) {
  try {
    final key = encrypt.Key.fromUtf8(secretKeyString);
    final ivv = encrypt.IV.fromUtf8(iv);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
    );
    if (doEncrypt) {
      return encrypter.encrypt(text, iv: ivv).base64;
    }
    return encrypter.decrypt64(text, iv: ivv);
  } catch (_) {
    return text;
  }
}

class GogoCdnExtractor {
  final JsonCodec json = const JsonCodec();

  Future<List<Video>> videosFromUrl(String serverUrl) async {
    final client = extractorClient();
    try {
      final response = await client.get(Uri.parse(serverUrl));
      final document = response.body;

      final Document parsedResponse = parser.parse(response.body);
      final iv = parsedResponse
          .querySelector('div.wrapper')!
          .attributes["class"]!
          .split('container-')
          .last;

      final secretKey = parsedResponse
          .querySelector('body[class]')!
          .attributes["class"]!
          .split('container-')
          .last;
      final decryptionKey = RegExp(
        r'videocontent-(\d+)',
      ).firstMatch(document)?.group(1);
      final encryptAjaxParams = _cryptoHandler(
        RegExp(r'data-value="([^"]+)').firstMatch(document)?.group(1) ?? "",
        iv,
        secretKey,
        false,
      ).substringAfter("&");

      final httpUrl = Uri.parse(serverUrl);
      final host = "https://${httpUrl.host}/";
      final id = httpUrl.queryParameters['id'];
      final encryptedId = _cryptoHandler(id ?? "", iv, secretKey, true);

      final token = httpUrl.queryParameters['token'];
      final qualityPrefix = token != null ? "Gogostream - " : "Vidstreaming - ";

      final encryptAjaxUrl =
          "${host}encrypt-ajax.php?id=$encryptedId&$encryptAjaxParams&alias=$id";

      final encryptAjaxResponse = await client.get(
        Uri.parse(encryptAjaxUrl),
        headers: {"X-Requested-With": "XMLHttpRequest"},
      );
      final jsonResponse = encryptAjaxResponse.body;
      final data = json.decode(jsonResponse)["data"];
      final decryptedData = _cryptoHandler(
        data ?? "",
        iv,
        decryptionKey!,
        false,
      );
      final videoList = <Video>[];
      final autoList = <Video>[];
      final array = json.decode(decryptedData)["source"];
      if (array != null &&
          array is List &&
          array.length == 1 &&
          array[0]["type"] == "hls") {
        final fileURL = array[0]["file"].toString().trim();
        const separator = "#EXT-X-STREAM-INF:";
        final masterPlaylistResponse = await client.get(Uri.parse(fileURL));
        final masterPlaylist = masterPlaylistResponse.body;
        if (masterPlaylist.contains(separator)) {
          for (var it
              in masterPlaylist.substringAfter(separator).split(separator)) {
            final quality =
                "${it.substringAfter("RESOLUTION=").substringAfter("x").substringBefore(",").substringBefore("\n")}p";

            var videoUrl = it.substringAfter("\n").substringBefore("\n");

            if (!videoUrl.startsWith("http")) {
              videoUrl =
                  "${fileURL.split("/").sublist(0, fileURL.split("/").length - 1).join("/")}/$videoUrl";
            }
            videoList.add(Video(videoUrl, "$qualityPrefix$quality", videoUrl));
          }
        } else {
          videoList.add(Video(fileURL, "${qualityPrefix}Original", fileURL));
        }
      } else if (array != null && array is List) {
        for (var it in array) {
          final label = it["label"].toString().toLowerCase().trim().replaceAll(
            " ",
            "",
          );
          final fileURL = it["file"].toString().trim();
          final videoHeaders = {"Referer": serverUrl};
          if (label == "auto") {
            autoList.add(
              Video(
                fileURL,
                "$qualityPrefix$label",
                fileURL,
                headers: videoHeaders,
              ),
            );
          } else {
            videoList.add(
              Video(
                fileURL,
                "$qualityPrefix$label",
                fileURL,
                headers: videoHeaders,
              ),
            );
          }
        }
      }
      return videoList + autoList;
    } catch (e) {
      return [];
    }
  }
}
