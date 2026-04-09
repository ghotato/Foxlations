import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a locally stored manga series.
class LocalManga {
  final String title;
  final String path;
  final String? coverPath;
  final String? author;
  final String? description;
  final List<String> genres;
  final String status;
  final List<LocalChapter> chapters;

  LocalManga({
    required this.title,
    required this.path,
    this.coverPath,
    this.author,
    this.description,
    this.genres = const [],
    this.status = 'Unknown',
    this.chapters = const [],
  });
}

/// Represents a locally stored chapter.
class LocalChapter {
  final String name;
  final String path; // folder path or archive file path
  final bool isArchive; // true if CBZ/ZIP/RAR/CBR/EPUB
  final int pageCount;

  LocalChapter({
    required this.name,
    required this.path,
    this.isArchive = false,
    this.pageCount = 0,
  });
}

/// Scans local folders for manga content.
///
/// Expected folder structure (like Tachimanga):
///   {localDir}/
///     {Manga Title}/
///       cover.jpg (optional)
///       details.json (optional)
///       {Chapter Name}/       ← folder with images
///         001.jpg, 002.png, ...
///       Chapter 1.cbz         ← or archive file
///       Chapter 2.zip
///       Volume 1.epub
class LocalSourceService {
  static LocalSourceService? _instance;
  factory LocalSourceService() => _instance ??= LocalSourceService._();
  LocalSourceService._();

  static const _foldersKey = 'local_source_folders';
  static const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif'};
  static const _archiveExts = {'cbz', 'zip', 'cbr', 'rar', 'epub'};

  /// Get saved local source folder paths.
  Future<List<String>> getFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_foldersKey) ?? [];
  }

  /// Add a local source folder.
  Future<void> addFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final folders = prefs.getStringList(_foldersKey) ?? [];
    if (!folders.contains(path)) {
      folders.add(path);
      await prefs.setStringList(_foldersKey, folders);
    }
  }

  /// Remove a local source folder.
  Future<void> removeFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final folders = prefs.getStringList(_foldersKey) ?? [];
    folders.remove(path);
    await prefs.setStringList(_foldersKey, folders);
  }

  /// Scan all local source folders for manga.
  Future<List<LocalManga>> scanAll() async {
    final folders = await getFolders();
    final allManga = <LocalManga>[];
    for (final folder in folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;
      final manga = await _scanFolder(dir);
      allManga.addAll(manga);
    }
    return allManga;
  }

  /// Scan a single folder for manga series.
  Future<List<LocalManga>> _scanFolder(Directory dir) async {
    final manga = <LocalManga>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final m = await _parseMangaDir(entity);
        if (m != null) manga.add(m);
      }
    }
    manga.sort((a, b) => a.title.compareTo(b.title));
    return manga;
  }

  /// Parse a manga directory.
  Future<LocalManga?> _parseMangaDir(Directory dir) async {
    final title = dir.path.split('/').last.split('\\').last;

    // Look for cover image
    String? coverPath;
    for (final ext in _imageExts) {
      final cover = File('${dir.path}/cover.$ext');
      if (await cover.exists()) {
        coverPath = cover.path;
        break;
      }
    }

    // Look for details.json
    String? author;
    String? description;
    List<String> genres = [];
    String status = 'Unknown';
    final detailsFile = File('${dir.path}/details.json');
    if (await detailsFile.exists()) {
      try {
        final json = jsonDecode(await detailsFile.readAsString());
        author = json['author'] as String?;
        description = json['description'] as String?;
        genres = (json['genre'] as List?)?.cast<String>() ?? [];
        status = json['status'] as String? ?? 'Unknown';
      } catch (_) {}
    }

    // Scan for chapters (subfolders and archive files)
    final chapters = <LocalChapter>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        // Chapter folder with images
        final name = entity.path.split('/').last.split('\\').last;
        if (name == '.') continue;
        final imageCount = await _countImages(entity);
        if (imageCount > 0) {
          chapters.add(LocalChapter(
            name: name,
            path: entity.path,
            pageCount: imageCount,
          ));
        }
      } else if (entity is File) {
        final ext = entity.path.split('.').last.toLowerCase();
        final name = entity.path.split('/').last.split('\\').last;
        // Skip cover and details files
        if (name.startsWith('cover.') || name == 'details.json') continue;
        if (_archiveExts.contains(ext)) {
          chapters.add(LocalChapter(
            name: name.replaceAll(RegExp(r'\.[^.]+$'), ''), // strip extension
            path: entity.path,
            isArchive: true,
          ));
        }
      }
    }

    if (chapters.isEmpty) return null;

    // Sort chapters alphanumerically
    chapters.sort((a, b) => a.name.compareTo(b.name));

    // Use first image in first chapter as cover if no cover.jpg
    if (coverPath == null && chapters.isNotEmpty && !chapters.first.isArchive) {
      final firstChapterImages = await _getImagePaths(Directory(chapters.first.path));
      if (firstChapterImages.isNotEmpty) {
        coverPath = firstChapterImages.first;
      }
    }

    return LocalManga(
      title: title,
      path: dir.path,
      coverPath: coverPath,
      author: author,
      description: description,
      genres: genres,
      status: status,
      chapters: chapters,
    );
  }

  /// Count image files in a directory.
  Future<int> _countImages(Directory dir) async {
    int count = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        final ext = entity.path.split('.').last.toLowerCase();
        if (_imageExts.contains(ext)) count++;
      }
    }
    return count;
  }

  /// Get sorted image paths from a chapter folder.
  Future<List<String>> _getImagePaths(Directory dir) async {
    final paths = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final ext = entity.path.split('.').last.toLowerCase();
        if (_imageExts.contains(ext)) paths.add(entity.path);
      }
    }
    paths.sort();
    return paths;
  }

  /// Get pages from a chapter (folder or archive).
  /// Returns list of file paths (for folders) or extracted image bytes info.
  Future<List<String>> getChapterPages(LocalChapter chapter) async {
    if (!chapter.isArchive) {
      return _getImagePaths(Directory(chapter.path));
    }
    // For archives, extract to a temp directory and return paths
    return _extractArchivePages(chapter.path);
  }

  /// Extract images from an archive file (CBZ/ZIP/CBR/RAR/EPUB).
  /// Returns list of temp file paths.
  Future<List<String>> _extractArchivePages(String archivePath) async {
    final ext = archivePath.split('.').last.toLowerCase();
    final file = File(archivePath);
    if (!await file.exists()) return [];

    try {
      final bytes = await file.readAsBytes();
      Archive archive;

      if (ext == 'cbz' || ext == 'zip') {
        archive = ZipDecoder().decodeBytes(bytes);
      } else if (ext == 'cbr' || ext == 'rar') {
        // archive package doesn't support RAR natively
        // Fall back to treating as ZIP (some .cbr files are actually ZIP)
        try {
          archive = ZipDecoder().decodeBytes(bytes);
        } catch (_) {
          debugPrint('[LocalSource] RAR format not supported: $archivePath');
          return [];
        }
      } else if (ext == 'epub') {
        return _extractEpubPages(bytes);
      } else {
        return [];
      }

      // Extract images to temp directory
      final tempDir = Directory('${archivePath}_extracted');
      await tempDir.create(recursive: true);

      final pages = <String>[];
      final imageFiles = archive.files.where((f) {
        if (f.isFile) {
          final fExt = f.name.split('.').last.toLowerCase();
          return _imageExts.contains(fExt);
        }
        return false;
      }).toList();

      // Sort by name
      imageFiles.sort((a, b) => a.name.compareTo(b.name));

      for (int i = 0; i < imageFiles.length; i++) {
        final f = imageFiles[i];
        final outPath = '${tempDir.path}/${(i + 1).toString().padLeft(3, '0')}.jpg';
        final outFile = File(outPath);
        if (!await outFile.exists()) {
          await outFile.writeAsBytes(f.content as List<int>);
        }
        pages.add(outPath);
      }

      return pages;
    } catch (e) {
      debugPrint('[LocalSource] Error extracting $archivePath: $e');
      return [];
    }
  }

  /// Extract image pages from an EPUB file.
  Future<List<String>> _extractEpubPages(List<int> bytes) async {
    try {
      // EPUB is a ZIP with XHTML + images
      final archive = ZipDecoder().decodeBytes(bytes);
      final images = archive.files.where((f) {
        if (!f.isFile) return false;
        final ext = f.name.split('.').last.toLowerCase();
        return _imageExts.contains(ext);
      }).toList();

      images.sort((a, b) => a.name.compareTo(b.name));

      // Write to temp files
      final tempBase = Directory.systemTemp.path;
      final tempDir = Directory('$tempBase/foxlations_epub_${DateTime.now().millisecondsSinceEpoch}');
      await tempDir.create(recursive: true);

      final pages = <String>[];
      for (int i = 0; i < images.length; i++) {
        final outPath = '${tempDir.path}/${(i + 1).toString().padLeft(3, '0')}.jpg';
        await File(outPath).writeAsBytes(images[i].content as List<int>);
        pages.add(outPath);
      }
      return pages;
    } catch (e) {
      debugPrint('[LocalSource] EPUB extraction error: $e');
      return [];
    }
  }
}
