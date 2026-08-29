import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rhttp/rhttp.dart' as rhttp;
import 'cookie_store.dart';

/// Downloads manga chapter images to local storage.
///
/// Storage structure:
///   {downloadDir}/library/{sourceId}/{mangaTitle}/{chapterName}/001.jpg
///   {downloadDir}/vault/{sourceId}/{mangaTitle}/{chapterName}/001.jpg
class DownloadService {
  static DownloadService? _instance;
  factory DownloadService() => _instance ??= DownloadService._();
  DownloadService._();

  rhttp.RhttpClient? _client;
  static const _downloadPathKey = 'download_path';

  Future<rhttp.RhttpClient> _getClient() async {
    if (_client != null) return _client!;
    _client = await rhttp.RhttpClient.create(
      settings: const rhttp.ClientSettings(
        throwOnStatusCode: false,
        tlsSettings: rhttp.TlsSettings(verifyCertificates: false),
      ),
    );
    return _client!;
  }

  /// Get the base download directory. Uses custom path if set, otherwise app documents.
  Future<String> getBasePath() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_downloadPathKey);
    if (custom != null && custom.isNotEmpty && await Directory(custom).exists()) {
      return custom;
    }
    // Default path
    final dir = await getApplicationDocumentsDirectory();
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Foxlations/downloads';
    }
    return '${dir.path}/Foxlations/downloads';
  }

  /// Set a custom download directory.
  Future<void> setDownloadPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadPathKey, path);
  }

  /// Clear custom download path (revert to default).
  Future<void> clearDownloadPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_downloadPathKey);
  }

  /// Get the current download path setting (empty = default).
  Future<String> getDownloadPathSetting() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_downloadPathKey) ?? '';
  }

  /// Sanitize a string for use as a directory name.
  String _sanitize(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\.+$'), '')
        .trim();
  }

  /// Get the directory path for a chapter's downloaded images.
  /// [isVault] separates vault downloads from library downloads.
  Future<String> getChapterDir(
      String sourceId, String mangaTitle, String chapterName,
      {bool isVault = false}) async {
    final base = await getBasePath();
    final section = isVault ? 'vault' : 'library';
    final sanitizedManga = _sanitize(mangaTitle);
    final sanitizedChapter = _sanitize(chapterName);
    return '$base/$section/$sourceId/$sanitizedManga/$sanitizedChapter';
  }

  /// Check if a chapter is fully downloaded.
  Future<bool> isChapterDownloaded(
      String sourceId, String mangaTitle, String chapterName,
      {bool isVault = false}) async {
    final dir = await getChapterDir(sourceId, mangaTitle, chapterName, isVault: isVault);
    final d = Directory(dir);
    if (!await d.exists()) return false;
    final count = await d.list().where((f) => f.path.endsWith('.jpg')).length;
    return count > 0;
  }

  /// Get local image paths for a downloaded chapter (sorted).
  Future<List<String>> getLocalPages(
      String sourceId, String mangaTitle, String chapterName,
      {bool isVault = false}) async {
    final dir = await getChapterDir(sourceId, mangaTitle, chapterName, isVault: isVault);
    final d = Directory(dir);
    if (!await d.exists()) return [];
    final files = await d.list().toList();
    final jpgs = files
        .where((f) => f.path.endsWith('.jpg'))
        .map((f) => f.path)
        .toList();
    jpgs.sort();
    return jpgs;
  }

  /// Download a chapter's images.
  Future<bool> downloadChapter({
    required String sourceId,
    required String mangaTitle,
    required String chapterName,
    required List<String> imageUrls,
    Map<String, String> headers = const {},
    bool isVault = false,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (imageUrls.isEmpty) return false;

    final dir = await getChapterDir(sourceId, mangaTitle, chapterName, isVault: isVault);
    await Directory(dir).create(recursive: true);

    final client = await _getClient();
    final cookieStore = CookieStore();
    final storedUA = await cookieStore.getUserAgent();

    int completed = 0;
    int failed = 0;

    for (int i = 0; i < imageUrls.length; i++) {
      final url = imageUrls[i];
      final fileName = '${(i + 1).toString().padLeft(3, '0')}.jpg';
      final filePath = '$dir/$fileName';

      // Skip if already downloaded
      if (await File(filePath).exists()) {
        completed++;
        onProgress?.call(completed, imageUrls.length);
        continue;
      }

      // Build headers
      final mergedHeaders = Map<String, String>.from(headers);
      final cookieHeader = await cookieStore.getCookieHeader(url);
      if (cookieHeader != null) mergedHeaders['Cookie'] = cookieHeader;
      mergedHeaders.putIfAbsent('User-Agent', () => storedUA);

      // Download with retry
      bool success = false;
      for (int attempt = 0; attempt < 3 && !success; attempt++) {
        try {
          final response = await client.requestBytes(
            method: rhttp.HttpMethod.get,
            url: url,
            headers: rhttp.HttpHeaders.rawMap(mergedHeaders),
          );
          if (response.statusCode == 200 && response.body.isNotEmpty) {
            await File(filePath).writeAsBytes(response.body);
            success = true;
          }
        } catch (e) {
          debugPrint('[Download] Retry ${attempt + 1}/3 for $url: $e');
          if (attempt < 2) await Future.delayed(Duration(seconds: attempt + 1));
        }
      }

      if (success) {
        completed++;
      } else {
        failed++;
        debugPrint('[Download] Failed after 3 attempts: $url');
      }
      onProgress?.call(completed, imageUrls.length);
    }

    debugPrint('[Download] Chapter "$chapterName": $completed/${imageUrls.length} '
        '(${failed > 0 ? "$failed failed" : "complete"})');
    return failed == 0;
  }

  /// Delete a downloaded chapter (folder or CBZ file).
  Future<void> deleteChapter(
      String sourceId, String mangaTitle, String chapterName,
      {bool isVault = false}) async {
    // Try deleting the image folder
    final dir = await getChapterDir(sourceId, mangaTitle, chapterName, isVault: isVault);
    final d = Directory(dir);
    if (await d.exists()) {
      await d.delete(recursive: true);
      debugPrint('[Download] Deleted folder: $dir');
      return;
    }

    // Try deleting a packaged CBZ/PDF file
    final base = await getBasePath();
    final section = isVault ? 'vault' : 'library';
    final mangaDir = '$base/$section/$sourceId/${_sanitize(mangaTitle)}';
    for (final ext in ['cbz', 'pdf']) {
      final packedPath = '$mangaDir/${_sanitize(chapterName)}.$ext';
      final packedFile = File(packedPath);
      if (await packedFile.exists()) {
        await packedFile.delete();
        debugPrint('[Download] Deleted ${ext.toUpperCase()}: $packedPath');
        return;
      }
    }

    // Also try both vault and library if isVault wasn't specified correctly
    for (final sec in ['library', 'vault']) {
      final tryDir = '$base/$sec/$sourceId/${_sanitize(mangaTitle)}/${_sanitize(chapterName)}';
      if (await Directory(tryDir).exists()) {
        await Directory(tryDir).delete(recursive: true);
        debugPrint('[Download] Deleted folder (found in $sec): $tryDir');
        return;
      }
      for (final ext in ['cbz', 'pdf']) {
        final tryPacked = '$tryDir.$ext';
        if (await File(tryPacked).exists()) {
          await File(tryPacked).delete();
          debugPrint('[Download] Deleted ${ext.toUpperCase()} (found in $sec): $tryPacked');
          return;
        }
      }
    }

    debugPrint('[Download] Nothing found to delete for "$chapterName" (source: $sourceId, manga: $mangaTitle)');
  }

  /// Delete all downloads for a manga.
  Future<void> deleteManga(String sourceId, String mangaTitle,
      {bool isVault = false}) async {
    final base = await getBasePath();
    final section = isVault ? 'vault' : 'library';
    final dir = Directory('$base/$section/$sourceId/${_sanitize(mangaTitle)}');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Convert a downloaded chapter folder to a CBZ archive.
  /// Returns the CBZ file path, or null on failure.
  Future<String?> convertToCbz({
    required String sourceId,
    required String mangaTitle,
    required String chapterName,
    bool isVault = false,
    String? author,
    String? description,
    List<String>? genres,
  }) async {
    final dir = await getChapterDir(sourceId, mangaTitle, chapterName, isVault: isVault);
    final d = Directory(dir);
    if (!await d.exists()) return null;

    final files = await d.list().toList();
    final images = files.where((f) {
      final ext = f.path.split('.').last.toLowerCase();
      return ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp' || ext == 'gif';
    }).toList();
    images.sort((a, b) => a.path.compareTo(b.path));

    if (images.isEmpty) return null;

    final archive = Archive();

    // Add images
    for (final img in images) {
      final bytes = await File(img.path).readAsBytes();
      final name = img.path.split('/').last.split('\\').last;
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    // Add ComicInfo.xml metadata
    final comicInfo = StringBuffer();
    comicInfo.writeln('<?xml version="1.0" encoding="utf-8"?>');
    comicInfo.writeln('<ComicInfo>');
    comicInfo.writeln('  <Series>${_xmlEscape(mangaTitle)}</Series>');
    comicInfo.writeln('  <Title>${_xmlEscape(chapterName)}</Title>');
    if (author != null) comicInfo.writeln('  <Writer>${_xmlEscape(author)}</Writer>');
    if (description != null) comicInfo.writeln('  <Summary>${_xmlEscape(description)}</Summary>');
    if (genres != null && genres.isNotEmpty) {
      comicInfo.writeln('  <Genre>${_xmlEscape(genres.join(', '))}</Genre>');
    }
    comicInfo.writeln('  <PageCount>${images.length}</PageCount>');
    comicInfo.writeln('</ComicInfo>');

    final xmlBytes = utf8.encode(comicInfo.toString());
    archive.addFile(ArchiveFile('ComicInfo.xml', xmlBytes.length, xmlBytes));

    // Write CBZ
    final encoder = ZipEncoder();
    final zipData = encoder.encode(archive);

    final base = await getBasePath();
    final section = isVault ? 'vault' : 'library';
    final mangaDir = '$base/$section/$sourceId/${_sanitize(mangaTitle)}';
    final cbzPath = '$mangaDir/${_sanitize(chapterName)}.cbz';
    await File(cbzPath).writeAsBytes(zipData);

    // Optionally delete the image folder after archiving
    await d.delete(recursive: true);

    debugPrint('[Download] Created CBZ: $cbzPath (${(zipData.length / 1024).toStringAsFixed(0)} KB)');
    return cbzPath;
  }

  /// Convert a downloaded chapter folder to a single PDF (one image per page).
  /// Each page is sized to its image so aspect ratio is preserved and there are
  /// no margins. Returns the PDF path, or null on failure.
  Future<String?> convertToPdf({
    required String sourceId,
    required String mangaTitle,
    required String chapterName,
    bool isVault = false,
    bool deleteFolder = true,
  }) async {
    final dir = await getChapterDir(sourceId, mangaTitle, chapterName, isVault: isVault);
    final d = Directory(dir);
    if (!await d.exists()) return null;

    final files = await d.list().toList();
    final images = files.where((f) {
      final ext = f.path.split('.').last.toLowerCase();
      return ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp' || ext == 'gif';
    }).toList();
    images.sort((a, b) => a.path.compareTo(b.path));

    if (images.isEmpty) return null;

    final doc = pw.Document();
    int pageCount = 0;

    for (final imgFile in images) {
      final raw = await File(imgFile.path).readAsBytes();
      // The PDF `MemoryImage` only accepts JPEG/PNG. Downloaded pages are named
      // .jpg but may actually be webp/gif bytes, so decode + re-encode to JPEG
      // to guarantee a valid, embeddable image and known dimensions.
      final normalized = _toJpegForPdf(raw);
      if (normalized == null) {
        debugPrint('[Download] Skipping undecodable page: ${imgFile.path}');
        continue;
      }
      final memImage = pw.MemoryImage(normalized.bytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            normalized.width.toDouble(),
            normalized.height.toDouble(),
          ),
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Center(
            child: pw.Image(memImage, fit: pw.BoxFit.contain),
          ),
        ),
      );
      pageCount++;
    }

    if (pageCount == 0) return null;

    final base = await getBasePath();
    final section = isVault ? 'vault' : 'library';
    final mangaDir = '$base/$section/$sourceId/${_sanitize(mangaTitle)}';
    final pdfPath = '$mangaDir/${_sanitize(chapterName)}.pdf';
    final bytes = await doc.save();
    await File(pdfPath).writeAsBytes(bytes);

    if (deleteFolder) await d.delete(recursive: true);

    debugPrint('[Download] Created PDF: $pdfPath (${(bytes.length / 1024).toStringAsFixed(0)} KB, $pageCount pages)');
    return pdfPath;
  }

  /// Decode arbitrary image bytes and re-encode as JPEG for PDF embedding.
  /// Returns the JPEG bytes plus pixel dimensions, or null if undecodable.
  ({Uint8List bytes, int width, int height})? _toJpegForPdf(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    final jpg = img.encodeJpg(decoded, quality: 90);
    return (bytes: jpg, width: decoded.width, height: decoded.height);
  }

  /// Get the directory path for an anime series' downloaded episodes.
  Future<String> getAnimeDir(String sourceId, String animeTitle) async {
    final base = await getBasePath();
    return '$base/library/$sourceId/${_sanitize(animeTitle)}';
  }

  /// Check if an episode is downloaded.
  Future<bool> isEpisodeDownloaded(
      String sourceId, String animeTitle, String episodeName) async {
    final dir = await getAnimeDir(sourceId, animeTitle);
    final name = _sanitize(episodeName);
    for (final ext in ['mp4', 'mkv', 'ts', 'webm']) {
      if (await File('$dir/$name.$ext').exists()) return true;
    }
    return false;
  }

  /// Get the local file path for a downloaded episode (null if not found).
  Future<String?> getEpisodePath(
      String sourceId, String animeTitle, String episodeName) async {
    final dir = await getAnimeDir(sourceId, animeTitle);
    final name = _sanitize(episodeName);
    for (final ext in ['mp4', 'mkv', 'ts', 'webm']) {
      final path = '$dir/$name.$ext';
      if (await File(path).exists()) return path;
    }
    return null;
  }

  /// Download an anime episode. Handles direct video URLs and HLS (.m3u8).
  /// Progress callback receives (bytesReceived, totalBytes) — total is -1 for
  /// HLS until the segment count is known, then switches to (segmentsDone, segmentsTotal).
  Future<bool> downloadEpisode({
    required String sourceId,
    required String animeTitle,
    required String episodeName,
    required String videoUrl,
    Map<String, String> headers = const {},
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await getAnimeDir(sourceId, animeTitle);
    await Directory(dir).create(recursive: true);
    final name = _sanitize(episodeName);

    if (videoUrl.contains('.m3u8')) {
      return _downloadHls(videoUrl, dir, name, headers, onProgress);
    } else {
      final ext = _videoExtension(videoUrl);
      return _downloadDirect(videoUrl, '$dir/$name.$ext', headers, onProgress);
    }
  }

  String _videoExtension(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final ext = path.split('.').last.toLowerCase().split('?').first;
    const known = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'ts'};
    return known.contains(ext) ? ext : 'mp4';
  }

  /// Download a direct video file using Dio (streams to disk, tracks progress).
  Future<bool> _downloadDirect(
    String url,
    String savePath,
    Map<String, String> headers,
    void Function(int, int)? onProgress,
  ) async {
    if (await File(savePath).exists()) return true;
    final cookieStore = CookieStore();
    final storedUA = await cookieStore.getUserAgent();
    final cookieHeader = await cookieStore.getCookieHeader(url);

    final mergedHeaders = Map<String, String>.from(headers);
    mergedHeaders.putIfAbsent('User-Agent', () => storedUA);
    if (cookieHeader != null) mergedHeaders['Cookie'] = cookieHeader;

    final dio = Dio(BaseOptions(
      headers: mergedHeaders,
      receiveTimeout: const Duration(minutes: 30),
      connectTimeout: const Duration(seconds: 30),
    ));

    try {
      await dio.download(
        url,
        savePath,
        onReceiveProgress: onProgress,
      );
      return await File(savePath).exists();
    } catch (e) {
      debugPrint('[Download] Direct video failed: $e');
      return false;
    } finally {
      dio.close();
    }
  }

  /// Download an HLS stream by fetching all .ts segments and concatenating.
  Future<bool> _downloadHls(
    String m3u8Url,
    String dir,
    String name,
    Map<String, String> headers,
    void Function(int, int)? onProgress,
  ) async {
    final savePath = '$dir/$name.ts';
    if (await File(savePath).exists()) return true;

    final cookieStore = CookieStore();
    final storedUA = await cookieStore.getUserAgent();
    final cookieHeader = await cookieStore.getCookieHeader(m3u8Url);

    final mergedHeaders = Map<String, String>.from(headers);
    mergedHeaders.putIfAbsent('User-Agent', () => storedUA);
    if (cookieHeader != null) mergedHeaders['Cookie'] = cookieHeader;

    final dio = Dio(BaseOptions(
      headers: mergedHeaders,
      receiveTimeout: const Duration(minutes: 5),
      connectTimeout: const Duration(seconds: 30),
    ));

    try {
      // Fetch the playlist
      final playlistRes = await dio.get<String>(m3u8Url);
      var playlist = playlistRes.data ?? '';

      // If master playlist (has #EXT-X-STREAM-INF), pick the first variant
      if (playlist.contains('#EXT-X-STREAM-INF')) {
        final variantLine = playlist
            .split('\n')
            .firstWhere((l) => l.trim().isNotEmpty && !l.startsWith('#'),
                orElse: () => '');
        if (variantLine.isEmpty) return false;
        final variantUrl = variantLine.startsWith('http')
            ? variantLine.trim()
            : '${m3u8Url.substring(0, m3u8Url.lastIndexOf('/') + 1)}${variantLine.trim()}';
        final variantRes = await dio.get<String>(variantUrl);
        playlist = variantRes.data ?? '';
        m3u8Url = variantUrl;
      }

      // Collect segment URLs
      final base = m3u8Url.substring(0, m3u8Url.lastIndexOf('/') + 1);
      final segments = playlist
          .split('\n')
          .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
          .map((l) => l.trim().startsWith('http') ? l.trim() : '$base${l.trim()}')
          .toList();

      if (segments.isEmpty) return false;
      onProgress?.call(0, segments.length);

      // Download segments and concatenate into a single .ts file
      final outFile = File(savePath).openWrite(mode: FileMode.writeOnly);
      int done = 0;
      for (final seg in segments) {
        try {
          final segRes = await dio.get<List<int>>(
            seg,
            options: Options(responseType: ResponseType.bytes),
          );
          if (segRes.data != null) outFile.add(segRes.data!);
        } catch (e) {
          debugPrint('[Download] HLS segment failed: $seg — $e');
        }
        done++;
        onProgress?.call(done, segments.length);
      }
      await outFile.close();
      return await File(savePath).exists();
    } catch (e) {
      debugPrint('[Download] HLS download failed: $e');
      return false;
    } finally {
      dio.close();
    }
  }

  String _xmlEscape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// Get total download size in bytes for library, vault, or both.
  Future<int> getTotalSize({bool? isVault}) async {
    final base = await getBasePath();
    final dirs = <String>[];
    if (isVault == null || !isVault) dirs.add('$base/library');
    if (isVault == null || isVault) dirs.add('$base/vault');

    int total = 0;
    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    }
    return total;
  }
}
