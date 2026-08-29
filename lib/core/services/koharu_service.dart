import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Client for the koharu local translation server.
/// Run with: docker run -p 4000:4000 mayocream/koharu:latest
class KoharuService {
  static Future<String> _baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('koharu_server_url') ?? 'http://localhost:4000').trimRight().replaceAll(RegExp(r'/$'), '');
  }

  /// Uploads [imageBytes], runs the full pipeline, and returns translated PNG bytes.
  Future<Uint8List> translatePage(
    Uint8List imageBytes, {
    String targetLang = 'en',
    String translator = 'google',
  }) async {
    final base = await _baseUrl();
    final client = http.Client();
    try {
      // 1. Upload image
      final uploadReq = http.MultipartRequest('POST', Uri.parse('$base/api/v1/pages'))
        ..files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: 'page.png'));
      final uploadResp = await uploadReq.send();
      if (uploadResp.statusCode != 200) {
        throw Exception('Koharu upload failed (${uploadResp.statusCode})');
      }
      final uploadBody = jsonDecode(await uploadResp.stream.bytesToString()) as Map<String, dynamic>;
      final pageId = uploadBody['id'] as String;

      // 2. Start pipeline
      final pipelineResp = await client.post(
        Uri.parse('$base/api/v1/pipelines'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pages': [pageId],
          'steps': ['detect', 'ocr', 'inpaint', 'translate', 'render'],
          'translator': translator,
          'target_language': targetLang,
        }),
      );
      if (pipelineResp.statusCode != 200) {
        throw Exception('Koharu pipeline failed (${pipelineResp.statusCode})');
      }
      final opId = (jsonDecode(pipelineResp.body) as Map<String, dynamic>)['id'] as String;

      // 3. Poll until finished (1.5s intervals, 60s timeout)
      for (int i = 0; i < 40; i++) {
        await Future.delayed(const Duration(milliseconds: 1500));
        final opsResp = await client.get(Uri.parse('$base/api/v1/operations'));
        if (opsResp.statusCode != 200) continue;
        final ops = jsonDecode(opsResp.body) as List<dynamic>;
        final op = ops.firstWhere((o) => o['id'] == opId, orElse: () => null);
        if (op == null) continue;
        final status = op['status'] as String?;
        if (status == 'finished') {
          // 4. Download blob
          final hash = op['output']?['hash'] as String?;
          if (hash == null) throw Exception('Koharu: no output hash in finished operation');
          final blobResp = await client.get(Uri.parse('$base/api/v1/blobs/$hash'));
          if (blobResp.statusCode != 200) {
            throw Exception('Koharu blob download failed (${blobResp.statusCode})');
          }
          return blobResp.bodyBytes;
        }
        if (status == 'error') {
          throw Exception('Koharu pipeline error: ${op['error'] ?? 'unknown'}');
        }
      }
      throw Exception('Koharu translation timed out after 60s');
    } finally {
      client.close();
    }
  }
}
