import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// Result of translating a manga page — list of detected text regions with translations.
class TranslationResult {
  final List<TranslatedRegion> regions;
  final String provider;
  final Duration elapsed;

  TranslationResult({required this.regions, required this.provider, required this.elapsed});
}

/// A detected text region with position, original text, and translation.
class TranslatedRegion {
  final double x; // 0.0-1.0 relative
  final double y;
  final double w;
  final double h;
  final String originalText;
  final String translatedText;

  TranslatedRegion({
    required this.x, required this.y, required this.w, required this.h,
    required this.originalText, required this.translatedText,
  });

  factory TranslatedRegion.fromJson(Map<String, dynamic> json) {
    final bbox = json['bbox'] ?? json['bounds'] ?? {};
    return TranslatedRegion(
      x: (bbox['x'] ?? json['x'] ?? 0).toDouble(),
      y: (bbox['y'] ?? json['y'] ?? 0).toDouble(),
      w: (bbox['w'] ?? json['w'] ?? bbox['width'] ?? 0).toDouble(),
      h: (bbox['h'] ?? json['h'] ?? bbox['height'] ?? 0).toDouble(),
      originalText: json['original'] ?? json['originalText'] ?? '',
      translatedText: json['translated'] ?? json['translatedText'] ?? '',
    );
  }
}

/// Translates manga pages using vision AI APIs.
/// Sends the full page image and gets back text regions with translations in one shot.
class AiTranslationService {
  static AiTranslationService? _instance;
  factory AiTranslationService() => _instance ??= AiTranslationService._();
  AiTranslationService._();

  static const _maxCacheSize = 50;
  final Map<String, TranslationResult> _cache = {};

  Future<(String provider, String apiKey)> _getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('ai_provider') ?? 'gemini';
    final apiKey = prefs.getString('api_key_$provider') ?? '';
    return (provider, apiKey);
  }

  Future<String> _getTargetLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ai_target_language') ?? 'en';
  }

  /// Shared HTTP POST helper for vision APIs. No TLS bypass on first-party APIs.
  Future<String> _postJson(String url, Map<String, String> headers, String body) async {
    final httpClient = HttpClient();
    try {
      final request = await httpClient.postUrl(Uri.parse(url));
      headers.forEach((k, v) => request.headers.set(k, v));
      request.write(body);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      debugPrint('[AI] ${Uri.parse(url).host} status: ${response.statusCode}, length: ${responseBody.length}');
      if (response.statusCode != 200) {
        debugPrint('[AI] Error: ${responseBody.substring(0, responseBody.length.clamp(0, 500))}');
        throw Exception('API error ${response.statusCode} from ${Uri.parse(url).host}');
      }
      return responseBody;
    } finally {
      httpClient.close();
    }
  }

  /// Translate a manga page image. Returns detected regions with translations.
  /// [imageBytes] - the page image as bytes (JPG/PNG/WebP)
  /// [cacheKey] - optional key for caching (e.g., "sourceId_chapterUrl_pageIndex")
  Future<TranslationResult> translatePage(Uint8List imageBytes, {String? cacheKey}) async {
    // Check cache
    if (cacheKey != null && _cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    final stopwatch = Stopwatch()..start();
    final (provider, apiKey) = await _getConfig();
    final targetLang = await _getTargetLanguage();

    if (apiKey.isEmpty) {
      throw Exception('No API key configured for $provider. Go to Settings > AI & Translation > API Keys.');
    }

    List<TranslatedRegion> regions;

    switch (provider) {
      case 'gemini':
        regions = await _translateWithGemini(imageBytes, apiKey, targetLang);
        break;
      case 'openai':
        regions = await _translateWithOpenAI(imageBytes, apiKey, targetLang);
        break;
      case 'claude':
        regions = await _translateWithClaude(imageBytes, apiKey, targetLang);
        break;
      case 'huggingface':
        regions = await _translateWithHuggingFace(imageBytes, apiKey, targetLang);
        break;
      case 'deepl':
        throw Exception('DeepL does not support image translation. Use Claude, OpenAI, Gemini, or Hugging Face.');
      default:
        throw Exception('Unsupported provider: $provider');
    }

    stopwatch.stop();
    final result = TranslationResult(
      regions: regions, provider: provider, elapsed: stopwatch.elapsed);

    if (cacheKey != null) {
      if (_cache.length >= _maxCacheSize) _cache.remove(_cache.keys.first);
      _cache[cacheKey] = result;
    }

    debugPrint('[AI] Translated ${regions.length} regions with $provider in ${stopwatch.elapsedMilliseconds}ms');
    return result;
  }

  /// Clear translation cache.
  void clearCache() => _cache.clear();

  // ── Gemini (Google) ────────────────────────────────────────

  Future<List<TranslatedRegion>> _translateWithGemini(
      Uint8List imageBytes, String apiKey, String targetLang) async {
    final model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: apiKey,
    );

    final prompt = _buildPrompt(targetLang);
    final content = Content.multi([
      TextPart(prompt),
      DataPart('image/jpeg', imageBytes),
    ]);

    final response = await model.generateContent([content]);
    final text = response.text ?? '';
    return _parseJsonResponse(text);
  }

  // ── OpenAI (GPT-4o) ───────────────────────────────────────

  Future<List<TranslatedRegion>> _translateWithOpenAI(
      Uint8List imageBytes, String apiKey, String targetLang) async {
    final b64Image = base64Encode(imageBytes);
    final prompt = _buildPrompt(targetLang);

    final body = jsonEncode({
      'model': 'gpt-4o-mini',
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$b64Image'}},
          ],
        },
      ],
      'max_tokens': 4096,
    });

    final responseBody = await _postJson(
      'https://api.openai.com/v1/chat/completions',
      {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body,
    );
    final data = jsonDecode(responseBody);
    final text = data['choices']?[0]?['message']?['content'] ?? '';
    return _parseJsonResponse(text);
  }

  // ── Claude (Anthropic) ─────────────────────────────────────

  Future<List<TranslatedRegion>> _translateWithClaude(
      Uint8List imageBytes, String apiKey, String targetLang) async {
    final b64Image = base64Encode(imageBytes);
    final prompt = _buildPrompt(targetLang);

    final body = jsonEncode({
      'model': 'claude-sonnet-4-20250514',
      'max_tokens': 4096,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'image', 'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': b64Image}},
            {'type': 'text', 'text': prompt},
          ],
        },
      ],
    });

    final responseBody = await _postJson(
      'https://api.anthropic.com/v1/messages',
      {'x-api-key': apiKey, 'anthropic-version': '2023-06-01', 'Content-Type': 'application/json'},
      body,
    );
    final data = jsonDecode(responseBody);
    final text = data['content']?[0]?['text'] ?? '';
    return _parseJsonResponse(text);
  }

  // ── Hugging Face ────────────────────────────────────────────

  Future<List<TranslatedRegion>> _translateWithHuggingFace(
      Uint8List imageBytes, String apiKey, String targetLang) async {
    // Strategy: Use manga-ocr for OCR on the full page, then translate with opus-mt
    // Since we can't get bounding boxes from HF API, we return a single region covering
    // the full page with all detected + translated text combined.
    // For better results, try the VLM endpoint first.

    // Try multimodal VLM first (Qwen2.5-VL) — same approach as Gemini/Claude
    try {
      final regions = await _translateWithHfVlm(imageBytes, apiKey, targetLang);
      if (regions.isNotEmpty) return regions;
    } catch (e) {
      debugPrint('[AI] HF VLM failed, falling back to OCR+translate pipeline: $e');
    }

    // Fallback: manga-ocr → opus-mt pipeline
    return _translateWithHfPipeline(imageBytes, apiKey, targetLang);
  }

  /// Try using a multimodal VLM on HF (like Gemini/Claude approach)
  Future<List<TranslatedRegion>> _translateWithHfVlm(
      Uint8List imageBytes, String apiKey, String targetLang) async {
    final b64Image = base64Encode(imageBytes);
    final prompt = _buildPrompt(targetLang);

    final body = jsonEncode({
      'model': 'Qwen/Qwen2.5-VL-7B-Instruct',
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$b64Image'}},
            {'type': 'text', 'text': prompt},
          ],
        },
      ],
      'max_tokens': 2048,
    });

    final responseBody = await _postJson(
      'https://api-inference.huggingface.co/models/Qwen/Qwen2.5-VL-7B-Instruct/v1/chat/completions',
      {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body,
    );
    final data = jsonDecode(responseBody);
    final text = data['choices']?[0]?['message']?['content'] ?? '';
    return _parseJsonResponse(text);
  }

  /// Fallback: manga-ocr for text extraction → opus-mt for translation
  Future<List<TranslatedRegion>> _translateWithHfPipeline(
      Uint8List imageBytes, String apiKey, String targetLang) async {
    // Step 1: OCR with manga-ocr-base
    final httpClient = HttpClient();
    String ocrText = '';
    try {
      final ocrRequest = await httpClient.postUrl(
          Uri.parse('https://api-inference.huggingface.co/models/kha-white/manga-ocr-base?wait_for_model=true'));
      ocrRequest.headers.set('Authorization', 'Bearer $apiKey');
      ocrRequest.add(imageBytes);
      final ocrResponse = await ocrRequest.close();
      final ocrBody = await ocrResponse.transform(utf8.decoder).join();
      debugPrint('[AI] HF OCR status: ${ocrResponse.statusCode}, length: ${ocrBody.length}');

      if (ocrResponse.statusCode == 200) {
        final ocrData = jsonDecode(ocrBody);
        if (ocrData is List && ocrData.isNotEmpty) {
          ocrText = ocrData[0]['generated_text'] ?? '';
        }
      }
    } catch (e) {
      debugPrint('[AI] HF OCR failed: $e');
    }

    if (ocrText.isEmpty) {
      httpClient.close();
      return [];
    }

    // Step 2: Translate with opus-mt
    final langModel = const {
      'en': 'Helsinki-NLP/opus-mt-ja-en',
      'zh': 'Helsinki-NLP/opus-mt-ja-zh',
      'ko': 'Helsinki-NLP/opus-mt-ja-ko',
      'fr': 'Helsinki-NLP/opus-mt-ja-fr',
      'de': 'Helsinki-NLP/opus-mt-ja-de',
      'es': 'Helsinki-NLP/opus-mt-ja-es',
    }[targetLang] ?? 'Helsinki-NLP/opus-mt-ja-en';

    String translatedText = '';
    try {
      final tlRequest = await httpClient.postUrl(
          Uri.parse('https://api-inference.huggingface.co/models/$langModel?wait_for_model=true'));
      tlRequest.headers.set('Authorization', 'Bearer $apiKey');
      tlRequest.headers.set('Content-Type', 'application/json');
      tlRequest.write(jsonEncode({'inputs': ocrText}));
      final tlResponse = await tlRequest.close();
      final tlBody = await tlResponse.transform(utf8.decoder).join();
      debugPrint('[AI] HF translate status: ${tlResponse.statusCode}');

      if (tlResponse.statusCode == 200) {
        final tlData = jsonDecode(tlBody);
        if (tlData is List && tlData.isNotEmpty) {
          translatedText = tlData[0]['translation_text'] ?? '';
        }
      }
    } catch (e) {
      debugPrint('[AI] HF translate failed: $e');
    } finally {
      httpClient.close();
    }

    if (translatedText.isEmpty) return [];

    // Return as a single centered region (no bounding box detection available)
    return [
      TranslatedRegion(
        x: 0.05, y: 0.02, w: 0.9, h: 0.08,
        originalText: ocrText,
        translatedText: translatedText,
      ),
    ];
  }

  // ── Shared helpers ─────────────────────────────────────────

  String _buildPrompt(String targetLang) {
    final langName = const {
      'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
      'pt': 'Portuguese', 'it': 'Italian', 'ru': 'Russian', 'zh': 'Chinese',
      'ko': 'Korean', 'ja': 'Japanese', 'ar': 'Arabic', 'tr': 'Turkish',
    }[targetLang] ?? 'English';

    return '''Analyze this manga/comic page. For each speech bubble or text region:
1. Detect its position as relative coordinates (0.0-1.0) from the top-left corner
2. OCR the original text
3. Translate it to $langName

Return ONLY a JSON array (no markdown, no explanation). Each element:
{"bbox":{"x":0.1,"y":0.2,"w":0.3,"h":0.1},"original":"original text","translated":"translated text"}

If no text is found, return an empty array: []''';
  }

  /// Parse the JSON response from any provider, handling markdown code blocks.
  List<TranslatedRegion> _parseJsonResponse(String text) {
    // Strip markdown code blocks if present
    var clean = text.trim();
    if (clean.startsWith('```')) {
      clean = clean.replaceFirst(RegExp(r'^```\w*\n?'), '');
      clean = clean.replaceFirst(RegExp(r'\n?```$'), '');
      clean = clean.trim();
    }

    try {
      final list = jsonDecode(clean);
      if (list is List) {
        return list.map((e) => TranslatedRegion.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('[AI] Failed to parse response: $e\nRaw: ${text.substring(0, text.length.clamp(0, 200))}');
    }
    return [];
  }
}
