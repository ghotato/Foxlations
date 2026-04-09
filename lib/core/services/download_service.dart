import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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

    // Try deleting CBZ file
    final base = await getBasePath();
    final section = isVault ? 'vault' : 'library';
    final cbzPath = '$base/$section/$sourceId/${_sanitize(mangaTitle)}/${_sanitize(chapterName)}.cbz';
    final cbzFile = File(cbzPath);
    if (await cbzFile.exists()) {
      await cbzFile.delete();
      debugPrint('[Download] Deleted CBZ: $cbzPath');
      return;
    }

    // Also try both vault and library if isVault wasn't specified correctly
    for (final sec in ['library', 'vault']) {
      final tryDir = '$base/$sec/$sourceId/${_sanitize(mangaTitle)}/${_sanitize(chapterName)}';
      if (await Directory(tryDir).exists()) {
        await Directory(tryDir).delete(recursive: true);
        debugPrint('[Download] Deleted folder (found in $sec): $tryDir');
        return;
      }
      final tryCbz = '$tryDir.cbz';
      if (await File(tryCbz).exists()) {
        await File(tryCbz).delete();
        debugPrint('[Download] Deleted CBZ (found in $sec): $tryCbz');
        return;
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
