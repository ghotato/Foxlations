import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/manga_model.dart';
import '../providers/library_provider.dart';
import '../providers/source_provider.dart';
import '../../eval/lib.dart';

/// Record of a new chapter found during update check.
class MangaUpdate {
  final String sourceId;
  final String mangaUrl;
  final String mangaTitle;
  final String coverUrl;
  final String chapterUrl;
  final String chapterName;
  final String dateFound;
  bool isRead;

  MangaUpdate({
    required this.sourceId,
    required this.mangaUrl,
    required this.mangaTitle,
    required this.coverUrl,
    required this.chapterUrl,
    required this.chapterName,
    required this.dateFound,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId, 'mangaUrl': mangaUrl, 'mangaTitle': mangaTitle,
    'coverUrl': coverUrl, 'chapterUrl': chapterUrl, 'chapterName': chapterName,
    'dateFound': dateFound, 'isRead': isRead,
  };

  factory MangaUpdate.fromJson(Map<String, dynamic> json) => MangaUpdate(
    sourceId: json['sourceId'] ?? '', mangaUrl: json['mangaUrl'] ?? '',
    mangaTitle: json['mangaTitle'] ?? '', coverUrl: json['coverUrl'] ?? '',
    chapterUrl: json['chapterUrl'] ?? '', chapterName: json['chapterName'] ?? '',
    dateFound: json['dateFound'] ?? '', isRead: json['isRead'] ?? false,
  );
}

/// Checks all library manga for new chapters.
class LibraryUpdateService {
  static const _updatesKey = 'manga_updates';
  static const _lastUpdateKey = 'last_library_update';

  static Future<List<MangaUpdate>> loadUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_updatesKey) ?? [];
    return raw.map((s) {
      try { return MangaUpdate.fromJson(jsonDecode(s)); }
      catch (_) { return null; }
    }).whereType<MangaUpdate>().toList();
  }

  static Future<void> saveUpdates(List<MangaUpdate> updates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_updatesKey,
        updates.map((u) => jsonEncode(u.toJson())).toList());
  }

  static Future<DateTime?> getLastUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastUpdateKey);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Checks the library for new chapters.
  ///
  /// [only] restricts the check to a subset — used by "Category Update" so it
  /// checks just the visible category instead of every entry.
  static Future<List<MangaUpdate>> checkForUpdates({
    required LibraryProvider libraryProvider,
    required SourceProvider sourceProvider,
    void Function(int checked, int total)? onProgress,
    List<LibraryManga>? only,
  }) async {
    final manga = only ?? libraryProvider.manga;
    final newUpdates = <MangaUpdate>[];
    int checked = 0;

    for (final m in manga) {
      try {
        final installed = sourceProvider.getInstalledSource(m.sourceId);
        if (installed == null) continue;

        final detail = await withExtensionService(
          installed.source, installed.sourceCode,
          (service) => service.getDetail(m.url),
        );

        if (detail.chapters == null) continue;

        // Get cached chapter URLs to diff against
        final cached = libraryProvider.getCachedChapters(m.sourceId, m.url);
        final cachedUrls = cached.map((c) => c.chapterUrl).toSet();

        final now = DateTime.now().toIso8601String();
        for (final ch in detail.chapters!) {
          if (ch.url != null && !cachedUrls.contains(ch.url)) {
            newUpdates.add(MangaUpdate(
              sourceId: m.sourceId,
              mangaUrl: m.url,
              mangaTitle: m.title,
              coverUrl: m.coverUrl,
              chapterUrl: ch.url!,
              chapterName: ch.name ?? 'New Chapter',
              dateFound: now,
            ));
          }
        }

        // Update cache
        if (detail.chapters!.isNotEmpty) {
          libraryProvider.cacheChapters(m.sourceId, m.url,
              detail.chapters!.map((c) => c.toJson()).toList());
        }
      } catch (e) {
        debugPrint('[Update] Error checking ${m.title}: $e');
      }

      checked++;
      onProgress?.call(checked, manga.length);
    }

    // Save timestamp
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastUpdateKey, DateTime.now().millisecondsSinceEpoch);

    // Merge with existing, keep max 500
    if (newUpdates.isNotEmpty) {
      final existing = await loadUpdates();
      final all = [...newUpdates, ...existing];
      if (all.length > 500) all.removeRange(500, all.length);
      await saveUpdates(all);
    }

    debugPrint('[Update] Checked ${manga.length} manga, found ${newUpdates.length} new chapters');
    return newUpdates;
  }

  static Future<void> clearUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_updatesKey);
  }

  static Future<int> getUnreadCount() async {
    final updates = await loadUpdates();
    return updates.where((u) => !u.isRead).length;
  }
}
