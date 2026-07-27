import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// Result of translating a manga page — list of detected text regions with translations.
class TranslationResult {
  final List<TranslatedRegion> regions;
  final String provider;
  final Duration elapsed;

  TranslationResult({required this.regions, required this.provider, required this.elapsed});

  Map<String, dynamic> toJson() => {
    'regions': regions.map((r) => r.toJson()).toList(),
    'provider': provider,
    'elapsedMs': elapsed.inMilliseconds,
  };

  factory TranslationResult.fromJson(Map<String, dynamic> json) => TranslationResult(
    regions: (json['regions'] as List).map((r) => TranslatedRegion.fromJson(r as Map<String, dynamic>)).toList(),
    provider: json['provider'] as String? ?? '',
    elapsed: Duration(milliseconds: (json['elapsedMs'] as num?)?.toInt() ?? 0),
  );
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

  Map<String, dynamic> toJson() => {
    'x': x, 'y': y, 'w': w, 'h': h,
    'original': originalText,
    'translated': translatedText,
  };
}

/// A text region detected by ML Kit — pixel-accurate position + raw OCR hint.
class _DetectedRegion {
  final Rect rect; // normalized 0.0-1.0
  final String text; // ML Kit OCR text (used as hint in LLM prompt)

  _DetectedRegion(this.rect, this.text);
}

/// Providers that don't need an API key.
const _freeProviders = {'googletranslate', 'mlkit'};

/// Translates manga pages using vision AI APIs.
/// Phase 1: ML Kit detects pixel-accurate text region positions (on Android/iOS).
/// Phase 2: Provider translates text in those positions (any language → any language).
class AiTranslationService {
  static AiTranslationService? _instance;
  factory AiTranslationService() => _instance ??= AiTranslationService._();
  AiTranslationService._();

  static const _maxCacheSize = 50;
  final Map<String, TranslationResult> _cache = {};

  /// Per-request output token budget for the LLM providers, set from the
  /// "Translation quality" setting at the top of each [translatePage]. A field
  /// rather than a threaded parameter so the individual _translateWith* methods
  /// stay untouched; pages translate one quality at a time so this is safe.
  int _maxTokens = 4096;

  Future<(String provider, String apiKey)> _getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    // "Offline Mode" (Settings > AI) forces the on-device ML Kit translator no
    // matter which provider is selected, so translation works with no network
    // and no API key. ML Kit only runs on Android/iOS; on desktop this simply
    // yields nothing rather than reaching out to a cloud API.
    if (prefs.getBool('offline_translation') ?? false) {
      return ('mlkit', '');
    }
    final provider = prefs.getString('ai_provider') ?? 'gemini';
    final apiKey = prefs.getString('api_key_$provider') ?? '';
    return (provider, apiKey);
  }

  /// Cap on translated characters per request, from Settings > AI >
  /// "Translation quality". Mapped to a token budget rather than swapping the
  /// model, so a higher tier can't accidentally name a model the user's API key
  /// has no access to (which would fail the whole translation). Higher = fuller
  /// output on dense pages; lower = faster and cheaper.
  Future<int> _maxTokensForQuality() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString('ai_translation_quality') ?? 'balanced') {
      case 'fast':
        return 2048;
      case 'best':
        return 8192;
      case 'balanced':
      default:
        return 4096;
    }
  }

  Future<String> _getTargetLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ai_target_language') ?? 'en';
  }

  /// Source language for OCR + ML Kit translation. 'auto' = run all scripts.
  Future<String> _getSourceLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    // Default to auto-detect. The old 'ja' default silently mis-OCR'd every
    // non-Japanese page (e.g. Korean read with the Japanese recogniser =
    // word-salad); 'auto' picks the right script per page.
    return prefs.getString('ai_source_language') ?? 'auto';
  }

  String _langForScript(TextRecognitionScript s) {
    if (s == TextRecognitionScript.korean) return 'ko';
    if (s == TextRecognitionScript.japanese) return 'ja';
    if (s == TextRecognitionScript.chinese) return 'zh';
    return 'en';
  }

  /// Shared HTTP POST helper for vision APIs.
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

  // ── Disk cache ─────────────────────────────────────────────

  String _sanitizeKey(String key) => key.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');

  Future<File> _diskCacheFile(String cacheKey) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/translations');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    return File('${cacheDir.path}/${_sanitizeKey(cacheKey)}.json');
  }

  Future<TranslationResult?> _loadFromDisk(String cacheKey) async {
    try {
      final file = await _diskCacheFile(cacheKey);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return TranslationResult.fromJson(json);
    } catch (e) {
      debugPrint('[AI] Disk cache read failed: $e');
      return null;
    }
  }

  Future<void> _saveToDisk(String cacheKey, TranslationResult result) async {
    try {
      final file = await _diskCacheFile(cacheKey);
      await file.writeAsString(jsonEncode(result.toJson()));
    } catch (e) {
      debugPrint('[AI] Disk cache write failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────

  /// Translate a manga page image. Returns detected regions with translations.
  Future<TranslationResult> translatePage(Uint8List imageBytes, {String? cacheKey}) async {
    // 1. Memory cache
    if (cacheKey != null && _cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // 2. Disk cache
    if (cacheKey != null) {
      final diskResult = await _loadFromDisk(cacheKey);
      if (diskResult != null) {
        debugPrint('[AI] Loaded translation from disk cache: $cacheKey');
        _cache[cacheKey] = diskResult;
        return diskResult;
      }
    }

    final stopwatch = Stopwatch()..start();
    final (provider, apiKey) = await _getConfig();
    final targetLang = await _getTargetLanguage();
    final sourceLang = await _getSourceLanguage();

    if (apiKey.isEmpty && !_freeProviders.contains(provider)) {
      throw Exception('No API key configured for $provider. Go to Settings > AI & Translation > API Keys.');
    }

    // Phase 1: ML Kit on-device detection for pixel-accurate bounding boxes.
    // Use only the configured source language script (not all 4) to avoid noise.
    //
    // "Bubble detection" (Settings > AI): when on, ML Kit finds precise text
    // boxes to translate in place; when off, we hand the whole page to the LLM
    // and let it locate text itself (LLM-only mode). The on-device 'mlkit'
    // provider has nothing to translate without boxes, so it always detects
    // regardless of the toggle.
    final prefs = await SharedPreferences.getInstance();
    final bubbleDetection = prefs.getBool('ai_bubble_detection') ?? true;
    _maxTokens = await _maxTokensForQuality();
    List<_DetectedRegion> mlkitRegions = [];
    var effectiveSourceLang = sourceLang;
    if ((Platform.isAndroid || Platform.isIOS) &&
        (bubbleDetection || provider == 'mlkit')) {
      try {
        final (regions, detectedLang) =
            await _detectTextRegions(imageBytes, sourceLang);
        mlkitRegions = regions;
        effectiveSourceLang = detectedLang; // resolves 'auto' to the real script
        debugPrint('[AI] ML Kit detected ${mlkitRegions.length} regions (source: $effectiveSourceLang)');
      } catch (e) {
        debugPrint('[AI] ML Kit detection failed, using LLM-only mode: $e');
      }
    }

    // Phase 2: Translate using the selected provider.
    List<TranslatedRegion> regions;
    switch (provider) {
      case 'gemini':
        regions = await _translateWithGemini(imageBytes, apiKey, targetLang, mlkitRegions);
        break;
      case 'openai':
        regions = await _translateWithOpenAI(imageBytes, apiKey, targetLang, mlkitRegions);
        break;
      case 'openrouter':
        regions = await _translateWithOpenRouter(imageBytes, apiKey, targetLang, mlkitRegions);
        break;
      case 'claude':
        regions = await _translateWithClaude(imageBytes, apiKey, targetLang, mlkitRegions);
        break;
      case 'huggingface':
        regions = await _translateWithHuggingFace(imageBytes, apiKey, targetLang, mlkitRegions);
        break;
      case 'googletranslate':
        regions = await _translateWithGoogleTranslate(targetLang, mlkitRegions);
        break;
      case 'mlkit':
        regions = await _translateWithMlKitTranslation(effectiveSourceLang, targetLang, mlkitRegions);
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
      await _saveToDisk(cacheKey, result);
    }

    debugPrint('[AI] Translated ${regions.length} regions with $provider in ${stopwatch.elapsedMilliseconds}ms');
    return result;
  }

  void clearCache() {
    _cache.clear();
  }

  // ── ML Kit text region detection ──────────────────────────────

  /// Map source language code → OCR script. TachiyomiAT uses one script per
  /// source language instead of running all 4 — this eliminates cross-script noise.
  TextRecognitionScript _toOcrScript(String langCode) {
    switch (langCode) {
      case 'ja': return TextRecognitionScript.japanese;
      case 'ko': return TextRecognitionScript.korean;
      case 'zh': return TextRecognitionScript.chinese;
      default:   return TextRecognitionScript.latin;
    }
  }

  /// Runs ML Kit and returns the detected regions plus the source language it
  /// settled on. For 'auto' it tries every script and keeps the ONE recogniser
  /// that read the most text — reading a page with the wrong script produces
  /// word-salad, and merging every recogniser's output invents text over the
  /// artwork. The winning script also tells the on-device translator the source
  /// language.
  Future<(List<_DetectedRegion>, String)> _detectTextRegions(
      Uint8List imageBytes, String sourceLang) async {
    final (imgW, imgH) = await _getImageSize(imageBytes);
    if (imgW == 0 || imgH == 0) return (<_DetectedRegion>[], sourceLang);

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/mlkit_scan_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await tempFile.writeAsBytes(imageBytes);
    final inputImage = InputImage.fromFilePath(tempFile.path);

    final auto = sourceLang == 'auto' || sourceLang.isEmpty;
    final scripts = auto
        ? const [TextRecognitionScript.latin, TextRecognitionScript.chinese,
                 TextRecognitionScript.japanese, TextRecognitionScript.korean]
        : [_toOcrScript(sourceLang)];

    var detectedLang = auto ? 'en' : sourceLang;
    final chosen = <(Rect, String)>[];
    try {
      final results = await Future.wait(scripts.map((script) async {
        final recognizer = TextRecognizer(script: script);
        try {
          return (script, await recognizer.processImage(inputImage));
        } finally {
          recognizer.close();
        }
      }));

      // Score each recogniser by how much non-whitespace text it read; the
      // correct script reads dense, coherent text while wrong scripts read
      // sparse fragments. Keep only the winner's blocks.
      (TextRecognitionScript, RecognizedText)? best;
      var bestScore = -1;
      for (final r in results) {
        final score = r.$2.blocks
            .fold<int>(0, (s, b) => s + b.text.replaceAll(RegExp(r'\s'), '').length);
        if (score > bestScore) {
          bestScore = score;
          best = r;
        }
      }

      if (best != null) {
        if (auto) detectedLang = _langForScript(best.$1);
        for (final block in best.$2.blocks) {
          final text = block.text.trim();
          // A speech bubble has real words; a 1-char blob over artwork is
          // almost always a false positive.
          if (text.length < 2) continue;
          final bbox = block.boundingBox;
          chosen.add((
            Rect.fromLTRB(
              bbox.left / imgW, bbox.top / imgH,
              bbox.right / imgW, bbox.bottom / imgH,
            ),
            text,
          ));
        }
      }
    } finally {
      try { await tempFile.delete(); } catch (_) {}
    }

    if (chosen.isEmpty) return (<_DetectedRegion>[], detectedLang);

    final merged = _mergeNearbyBlocks(chosen, 0.03);
    final regions =
        merged.where((r) => r.rect.width > 0.02 && r.rect.height > 0.01).toList();
    return (regions, detectedLang);
  }

  Future<(int, int)> _getImageSize(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    final image = await completer.future;
    final size = (image.width, image.height);
    image.dispose();
    return size;
  }

  List<_DetectedRegion> _mergeNearbyBlocks(List<(Rect, String)> blocks, double threshold) {
    if (blocks.isEmpty) return [];

    final sorted = List.of(blocks)
      ..sort((a, b) {
        final dy = a.$1.top.compareTo(b.$1.top);
        return dy != 0 ? dy : a.$1.left.compareTo(b.$1.left);
      });

    final used = List.filled(sorted.length, false);
    final result = <_DetectedRegion>[];

    for (int i = 0; i < sorted.length; i++) {
      if (used[i]) continue;
      var mergedRect = sorted[i].$1;
      final texts = <String>[sorted[i].$2];
      used[i] = true;

      for (int j = i + 1; j < sorted.length; j++) {
        if (used[j]) continue;
        if (_rectsAreNear(mergedRect, sorted[j].$1, threshold)) {
          mergedRect = _expandRect(mergedRect, sorted[j].$1);
          texts.add(sorted[j].$2);
          used[j] = true;
        }
      }

      result.add(_DetectedRegion(mergedRect, texts.join('\n')));
    }

    return result;
  }

  bool _rectsAreNear(Rect a, Rect b, double threshold) {
    if (a.overlaps(b)) return true;
    final hGap = max(0.0, max(b.left - a.right, a.left - b.right));
    final vGap = max(0.0, max(b.top - a.bottom, a.top - b.bottom));
    return hGap < threshold && vGap < threshold;
  }

  Rect _expandRect(Rect a, Rect b) => Rect.fromLTRB(
    min(a.left, b.left), min(a.top, b.top),
    max(a.right, b.right), max(a.bottom, b.bottom),
  );

  // ── Google Translate (free, ported from TachiyomiAT) ───────────

  /// Free Google Translate using the token-authenticated endpoint.
  /// Ported directly from TachiyomiAT's GoogleTranslator.kt.
  Future<List<TranslatedRegion>> _translateWithGoogleTranslate(
      String targetLang, List<_DetectedRegion> mlkitRegions) async {
    if (mlkitRegions.isEmpty) {
      throw Exception(
          'Google Translate requires text detection, which is only available on Android/iOS.');
    }

    final gtLang = _toGoogleTranslateLang(targetLang);
    final httpClient = HttpClient();
    final results = <TranslatedRegion>[];

    try {
      for (final region in mlkitRegions) {
        if (region.text.trim().isEmpty) continue;
        await Future.delayed(const Duration(milliseconds: 50));

        try {
          final url = _buildGoogleTranslateUrl(gtLang, region.text);
          final request = await httpClient.getUrl(Uri.parse(url));
          request.headers.set('User-Agent', 'Mozilla/5.0');
          final response = await request.close().timeout(const Duration(seconds: 10));
          final body = await response.transform(utf8.decoder).join();

          if (response.statusCode != 200) {
            debugPrint('[AI] Google Translate ${response.statusCode} for: ${region.text}');
            continue;
          }

          // Response: [[["translated","original",...],...],...]
          // TachiyomiAT parses: JSONArray(string).getJSONArray(0).getJSONArray(0).getString(0)
          final data = jsonDecode(body);
          if (data is! List || data.isEmpty) continue;
          final first = data[0];
          if (first is! List || first.isEmpty) continue;
          final firstEntry = first[0];
          if (firstEntry is! List || firstEntry.isEmpty) continue;
          final translated = firstEntry[0] as String? ?? '';

          if (translated.trim().isEmpty) continue;

          results.add(TranslatedRegion(
            x: region.rect.left, y: region.rect.top,
            w: region.rect.width, h: region.rect.height,
            originalText: region.text,
            translatedText: translated,
          ));
        } catch (e) {
          debugPrint('[AI] Google Translate failed for region: $e');
        }
      }
    } finally {
      httpClient.close();
    }

    return results;
  }

  /// Build the Google Translate URL with token. Ported from TachiyomiAT.
  String _buildGoogleTranslateUrl(String lang, String text) {
    final token = _calculateGoogleToken(text);
    final encoded = Uri.encodeComponent(text);
    return 'https://translate.google.com/translate_a/single?client=gtx&sl=auto&tl=$lang'
        '&dt=at&dt=bd&dt=ex&dt=ld&dt=md&dt=qca&dt=rw&dt=rm&dt=ss&dt=t'
        '&otf=1&ssel=0&tsel=0&kc=1&tk=$token&q=$encoded';
  }

  /// Token calculation ported from TachiyomiAT's GoogleTranslator.kt calculateToken().
  String _calculateGoogleToken(String text) {
    final list = <int>[];
    final units = text.codeUnits;
    int i = 0;

    while (i < units.length) {
      final c = units[i];
      if (c < 128) {
        list.add(c);
      } else if (c < 2048) {
        list.add((c >> 6) | 192);
        list.add((c & 63) | 128);
      } else if (c >= 55296 && c <= 57343 && i + 1 < units.length) {
        final next = units[i + 1];
        if (next >= 56320 && next <= 57343) {
          final cp = ((c & 1023) << 10) + (next & 1023) + 65536;
          list.add((cp >> 18) | 240);
          list.add(((cp >> 12) & 63) | 128);
          list.add(((cp >> 6) & 63) | 128);
          list.add((cp & 63) | 128);
          i++;
        }
      } else {
        list.add((c >> 12) | 224);
        list.add(((c >> 6) & 63) | 128);
        list.add((c & 63) | 128);
      }
      i++;
    }

    int j = 406644;
    for (final n in list) {
      j = _rl(j + n, '+-a^+6');
    }
    int result = _rl(j, '+-3^+b+-f') ^ 3293161072;
    if (result < 0) result = (result & 2147483647) + 2147483648;
    final j2 = result % 1000000;
    return '$j2.${406644 ^ j2}';
  }

  /// Bit-rotation helper. Ported from TachiyomiAT's RL() function.
  int _rl(int j, String str) {
    int result = j;
    int i = 0;
    while (i < str.length - 2) {
      final opChar = str[i + 2];
      final shift = (opChar.codeUnitAt(0) >= 'a'.codeUnitAt(0) &&
                     opChar.codeUnitAt(0) <= 'z'.codeUnitAt(0))
          ? opChar.codeUnitAt(0) - 'W'.codeUnitAt(0)
          : int.parse(opChar);
      // TachiyomiAT uses ushr (unsigned right shift) for '+', shl for '-'
      final shiftValue = str[i + 1] == '+' ? (result >>> shift) : (result << shift);
      result = str[i] == '+' ? (result + shiftValue) & 4294967295 : result ^ shiftValue;
      i += 3;
    }
    return result;
  }

  String _toGoogleTranslateLang(String code) => const {
    'en': 'en', 'es': 'es', 'fr': 'fr', 'de': 'de',
    'pt': 'pt', 'it': 'it', 'ru': 'ru',
    'zh': 'zh-CN', 'zh-TW': 'zh-TW',
    'ko': 'ko', 'ja': 'ja', 'ar': 'ar',
    'tr': 'tr', 'pl': 'pl',
  }[code] ?? 'en';

  // ── ML Kit On-Device Translation (ported from TachiyomiAT) ────

  /// Translates each text block line-by-line using ML Kit on-device translation.
  /// Ported from TachiyomiAT's MLKitTranslator — translates each \n-separated
  /// line individually then rejoins, which gives much cleaner results.
  Future<List<TranslatedRegion>> _translateWithMlKitTranslation(
      String sourceLang, String targetLang, List<_DetectedRegion> mlkitRegions) async {
    if (mlkitRegions.isEmpty) {
      throw Exception(
          'On-device translation requires text detection, which is only available on Android/iOS.');
    }

    final fromLang = _toMlKitLanguage(sourceLang == 'auto' ? 'ja' : sourceLang);
    final toLang = _toMlKitLanguage(targetLang);

    final translator = OnDeviceTranslator(
      sourceLanguage: fromLang,
      targetLanguage: toLang,
    );
    final modelManager = OnDeviceTranslatorModelManager();
    final results = <TranslatedRegion>[];

    try {
      // Download model if needed (like TachiyomiAT's downloadModelIfNeeded).
      final isDownloaded = await modelManager.isModelDownloaded(toLang.bcpCode);
      if (!isDownloaded) {
        debugPrint('[AI] Downloading ML Kit model for $targetLang...');
        await modelManager.downloadModel(toLang.bcpCode);
      }

      for (final region in mlkitRegions) {
        if (region.text.trim().isEmpty) continue;
        try {
          // TachiyomiAT: split("\n").mapNotNull { translate(it) }.joinToString("\n")
          final lines = region.text.split('\n');
          final translatedLines = await Future.wait(lines.map((line) async {
            if (line.trim().isEmpty) return line;
            try {
              return await translator.translateText(line);
            } catch (_) {
              return line; // keep original on error
            }
          }));
          final translated = translatedLines.join('\n');

          if (translated.trim().isEmpty) continue;
          results.add(TranslatedRegion(
            x: region.rect.left, y: region.rect.top,
            w: region.rect.width, h: region.rect.height,
            originalText: region.text,
            translatedText: translated,
          ));
        } catch (e) {
          debugPrint('[AI] ML Kit translate failed for region: $e');
        }
      }
    } finally {
      translator.close();
    }

    return results;
  }

  TranslateLanguage _toMlKitLanguage(String code) => const {
    'en': TranslateLanguage.english,
    'es': TranslateLanguage.spanish,
    'fr': TranslateLanguage.french,
    'de': TranslateLanguage.german,
    'pt': TranslateLanguage.portuguese,
    'it': TranslateLanguage.italian,
    'ru': TranslateLanguage.russian,
    'zh': TranslateLanguage.chinese,
    'zh-TW': TranslateLanguage.chinese,
    'ko': TranslateLanguage.korean,
    'ja': TranslateLanguage.japanese,
    'ar': TranslateLanguage.arabic,
    'tr': TranslateLanguage.turkish,
    'pl': TranslateLanguage.polish,
  }[code] ?? TranslateLanguage.english;

  // ── Gemini (Google) ────────────────────────────────────────

  Future<List<TranslatedRegion>> _translateWithGemini(
      Uint8List imageBytes, String apiKey, String targetLang,
      List<_DetectedRegion> mlkitRegions) async {
    final model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(maxOutputTokens: _maxTokens),
    );
    final prompt = _buildPrompt(targetLang, mlkitRegions);
    final content = Content.multi([TextPart(prompt), DataPart('image/jpeg', imageBytes)]);
    final response = await model.generateContent([content]);
    return _parseResponse(response.text ?? '', mlkitRegions);
  }

  // ── OpenAI (GPT-4o) ───────────────────────────────────────

  Future<List<TranslatedRegion>> _translateWithOpenAI(
      Uint8List imageBytes, String apiKey, String targetLang,
      List<_DetectedRegion> mlkitRegions) async {
    final b64Image = base64Encode(imageBytes);
    final body = jsonEncode({
      'model': 'gpt-4o-mini',
      'messages': [{'role': 'user', 'content': [
        {'type': 'text', 'text': _buildPrompt(targetLang, mlkitRegions)},
        {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$b64Image'}},
      ]}],
      'max_tokens': _maxTokens,
    });
    final responseBody = await _postJson(
      'https://api.openai.com/v1/chat/completions',
      {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'}, body);
    final data = jsonDecode(responseBody);
    return _parseResponse(data['choices']?[0]?['message']?['content'] ?? '', mlkitRegions);
  }

  // ── OpenRouter (OpenAI-compatible gateway; free models available) ──
  // Same request shape as OpenAI, different base URL + model. The model is
  // user-settable ('openrouter_model') because OpenRouter's free ":free" models
  // rotate; the default is a current free vision model that can OCR+translate
  // the page image directly. Needs a (free) OpenRouter API key.
  Future<List<TranslatedRegion>> _translateWithOpenRouter(
      Uint8List imageBytes, String apiKey, String targetLang,
      List<_DetectedRegion> mlkitRegions) async {
    final prefs = await SharedPreferences.getInstance();
    final model =
        prefs.getString('openrouter_model') ?? 'google/gemma-4-31b-it:free';
    final b64Image = base64Encode(imageBytes);
    final body = jsonEncode({
      'model': model,
      'messages': [{'role': 'user', 'content': [
        {'type': 'text', 'text': _buildPrompt(targetLang, mlkitRegions)},
        {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$b64Image'}},
      ]}],
      'max_tokens': _maxTokens,
    });
    final responseBody = await _postJson(
      'https://openrouter.ai/api/v1/chat/completions',
      {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        // OpenRouter attribution headers (optional but recommended).
        'HTTP-Referer': 'https://lillq.me/foxlations',
        'X-Title': 'Foxlations',
      },
      body,
    );
    final data = jsonDecode(responseBody);
    return _parseResponse(
        data['choices']?[0]?['message']?['content'] ?? '', mlkitRegions);
  }

  // ── Claude (Anthropic) ─────────────────────────────────────

  Future<List<TranslatedRegion>> _translateWithClaude(
      Uint8List imageBytes, String apiKey, String targetLang,
      List<_DetectedRegion> mlkitRegions) async {
    final b64Image = base64Encode(imageBytes);
    final body = jsonEncode({
      'model': 'claude-sonnet-4-20250514',
      'max_tokens': _maxTokens,
      'messages': [{'role': 'user', 'content': [
        {'type': 'image', 'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': b64Image}},
        {'type': 'text', 'text': _buildPrompt(targetLang, mlkitRegions)},
      ]}],
    });
    final responseBody = await _postJson(
      'https://api.anthropic.com/v1/messages',
      {'x-api-key': apiKey, 'anthropic-version': '2023-06-01', 'Content-Type': 'application/json'}, body);
    final data = jsonDecode(responseBody);
    return _parseResponse(data['content']?[0]?['text'] ?? '', mlkitRegions);
  }

  // ── Hugging Face ────────────────────────────────────────────

  Future<List<TranslatedRegion>> _translateWithHuggingFace(
      Uint8List imageBytes, String apiKey, String targetLang,
      List<_DetectedRegion> mlkitRegions) async {
    try {
      final regions = await _translateWithHfVlm(imageBytes, apiKey, targetLang, mlkitRegions);
      if (regions.isNotEmpty) return regions;
    } catch (e) {
      debugPrint('[AI] HF VLM failed, falling back: $e');
    }
    return _translateWithHfPipeline(imageBytes, apiKey, targetLang);
  }

  Future<List<TranslatedRegion>> _translateWithHfVlm(
      Uint8List imageBytes, String apiKey, String targetLang,
      List<_DetectedRegion> mlkitRegions) async {
    final b64Image = base64Encode(imageBytes);
    final body = jsonEncode({
      'model': 'Qwen/Qwen2.5-VL-7B-Instruct',
      'messages': [{'role': 'user', 'content': [
        {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$b64Image'}},
        {'type': 'text', 'text': _buildPrompt(targetLang, mlkitRegions)},
      ]}],
      'max_tokens': _maxTokens,
    });
    final responseBody = await _postJson(
      'https://api-inference.huggingface.co/models/Qwen/Qwen2.5-VL-7B-Instruct/v1/chat/completions',
      {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'}, body);
    final data = jsonDecode(responseBody);
    return _parseResponse(data['choices']?[0]?['message']?['content'] ?? '', mlkitRegions);
  }

  Future<List<TranslatedRegion>> _translateWithHfPipeline(
      Uint8List imageBytes, String apiKey, String targetLang) async {
    final httpClient = HttpClient();
    String ocrText = '';
    try {
      final ocrRequest = await httpClient.postUrl(Uri.parse(
          'https://api-inference.huggingface.co/models/kha-white/manga-ocr-base?wait_for_model=true'));
      ocrRequest.headers.set('Authorization', 'Bearer $apiKey');
      ocrRequest.add(imageBytes);
      final ocrResponse = await ocrRequest.close();
      final ocrBody = await ocrResponse.transform(utf8.decoder).join();
      if (ocrResponse.statusCode == 200) {
        final ocrData = jsonDecode(ocrBody);
        if (ocrData is List && ocrData.isNotEmpty) ocrText = ocrData[0]['generated_text'] ?? '';
      }
    } catch (e) {
      debugPrint('[AI] HF OCR failed: $e');
    }

    if (ocrText.isEmpty) { httpClient.close(); return []; }

    final langModel = const {
      'en': 'Helsinki-NLP/opus-mt-ja-en', 'zh': 'Helsinki-NLP/opus-mt-ja-zh',
      'ko': 'Helsinki-NLP/opus-mt-ja-ko', 'fr': 'Helsinki-NLP/opus-mt-ja-fr',
      'de': 'Helsinki-NLP/opus-mt-ja-de', 'es': 'Helsinki-NLP/opus-mt-ja-es',
    }[targetLang] ?? 'Helsinki-NLP/opus-mt-ja-en';

    String translatedText = '';
    try {
      final tlRequest = await httpClient.postUrl(Uri.parse(
          'https://api-inference.huggingface.co/models/$langModel?wait_for_model=true'));
      tlRequest.headers.set('Authorization', 'Bearer $apiKey');
      tlRequest.headers.set('Content-Type', 'application/json');
      tlRequest.write(jsonEncode({'inputs': ocrText}));
      final tlResponse = await tlRequest.close();
      final tlBody = await tlResponse.transform(utf8.decoder).join();
      if (tlResponse.statusCode == 200) {
        final tlData = jsonDecode(tlBody);
        if (tlData is List && tlData.isNotEmpty) translatedText = tlData[0]['translation_text'] ?? '';
      }
    } catch (e) {
      debugPrint('[AI] HF translate failed: $e');
    } finally {
      httpClient.close();
    }

    if (translatedText.isEmpty) return [];
    return [TranslatedRegion(x: 0.05, y: 0.02, w: 0.9, h: 0.08,
        originalText: ocrText, translatedText: translatedText)];
  }

  // ── Prompt builders ────────────────────────────────────────

  String _buildPrompt(String targetLang, List<_DetectedRegion> mlkitRegions) {
    final langName = const {
      'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
      'pt': 'Portuguese', 'it': 'Italian', 'ru': 'Russian',
      'zh': 'Simplified Chinese', 'zh-TW': 'Traditional Chinese',
      'ko': 'Korean', 'ja': 'Japanese', 'ar': 'Arabic',
      'tr': 'Turkish', 'pl': 'Polish',
    }[targetLang] ?? 'English';

    if (mlkitRegions.isEmpty) {
      return '''Analyze this manga/comic page. For each speech bubble or text region:
1. Detect its position as relative coordinates (0.0-1.0) from the top-left corner
2. OCR the original text
3. Translate it to $langName

Return ONLY a JSON array (no markdown, no explanation). Each element:
{"bbox":{"x":0.1,"y":0.2,"w":0.3,"h":0.1},"original":"original text","translated":"translated text"}

If no text is found, return an empty array: []''';
    }

    final regionHints = mlkitRegions.asMap().entries.map((e) {
      final i = e.key;
      final r = e.value;
      return '{"i":$i,"x":${r.rect.left.toStringAsFixed(3)},"y":${r.rect.top.toStringAsFixed(3)},"w":${r.rect.width.toStringAsFixed(3)},"h":${r.rect.height.toStringAsFixed(3)},"hint":${jsonEncode(r.text)}}';
    }).join(',');

    return '''The following text regions have been detected in this manga/comic page (coordinates are normalized 0.0-1.0):
[$regionHints]

For each region, look at that area of the image, read the text, and translate it to $langName.
Return ONLY a JSON array (no markdown):
[{"i":0,"original":"source text","translated":"$langName translation"},...]

Use exactly the index "i" from the input. Omit any region where no text is visible.''';
  }

  // ── Response parsing ───────────────────────────────────────

  List<TranslatedRegion> _parseResponse(String text, List<_DetectedRegion> mlkitRegions) {
    var clean = text.trim();
    if (clean.startsWith('```')) {
      clean = clean.replaceFirst(RegExp(r'^```\w*\n?'), '');
      clean = clean.replaceFirst(RegExp(r'\n?```$'), '');
      clean = clean.trim();
    }

    try {
      final list = jsonDecode(clean);
      if (list is! List) return [];

      if (mlkitRegions.isNotEmpty) {
        return list.map<TranslatedRegion?>((e) {
          final map = e as Map<String, dynamic>;
          final idx = (map['i'] as num?)?.toInt();
          if (idx == null || idx < 0 || idx >= mlkitRegions.length) return null;
          final r = mlkitRegions[idx].rect;
          return TranslatedRegion(
            x: r.left, y: r.top, w: r.width, h: r.height,
            originalText: map['original'] ?? '',
            translatedText: map['translated'] ?? '',
          );
        }).whereType<TranslatedRegion>().toList();
      }

      return list.map((e) => TranslatedRegion.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[AI] Failed to parse response: $e\nRaw: ${text.substring(0, text.length.clamp(0, 200))}');
    }
    return [];
  }
}
