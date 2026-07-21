import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/download_service.dart';
import '../../eval/lib.dart';
import '../providers/source_provider.dart';

/// Tracks download state for a single chapter or anime episode.
class DownloadTask {
  final String sourceId;
  final String mangaUrl;
  final String mangaTitle;
  final String chapterUrl;
  final String chapterName;
  final bool isVault;
  final bool isAnime;
  int completed;
  int total;
  DownloadStatus status;

  DownloadTask({
    required this.sourceId,
    required this.mangaUrl,
    required this.mangaTitle,
    required this.chapterUrl,
    required this.chapterName,
    this.isVault = false,
    this.isAnime = false,
    this.completed = 0,
    this.total = 0,
    this.status = DownloadStatus.queued,
  });

  String get key => '${sourceId}_$chapterUrl';
  double get progress => total > 0 ? completed / total : 0;
}

enum DownloadStatus { queued, downloading, completed, failed, cancelled }

/// Manages the download queue and tracks per-chapter download state.
class DownloadProvider extends ChangeNotifier {
  final DownloadService _downloadService = DownloadService();
  final List<DownloadTask> _queue = [];
  final Map<String, DownloadTask> _tasks = {};
  final Set<String> _downloadedChapters = {};
  bool _isProcessing = false;
  int _maxConcurrent = 2;
  int _activeCount = 0;

  // Settings (persisted in SharedPreferences). Wired keys:
  //   dl_auto              autoDownload
  //   dl_wifi_only         wifiOnly                (persisted only — no
  //                                                 connectivity check yet)
  //   dl_only_charging     onlyWhenCharging        (persisted only — no
  //                                                 battery plugin yet)
  //   dl_while_reading     downloadWhileReading    (consumed by reader_screen)
  //   dl_delete_after_read deleteAfterRead         (consumed by reader_screen)
  //   dl_remove_bookmarked removeBookmarked        (gates auto-delete)
  //   dl_auto_delete       autoDeleteAfter         (consumed by reader_screen)
  //   dl_save_cbz          saveAsCbz               (consumed in this file)
  //   dl_simultaneous      simultaneousDownloads   (consumed in _processQueue)
  //   dl_quality           downloadQuality         (persisted only — quality
  //                                                 selection is source-specific)
  bool autoDownload = false;
  bool wifiOnly = true;
  bool onlyWhenCharging = false;
  bool downloadWhileReading = false;
  bool deleteAfterRead = false;
  bool removeBookmarked = false;
  String autoDeleteAfter = 'Disabled';
  bool saveAsCbz = false;
  bool saveAsPdf = false;
  String simultaneousDownloads = '2';
  String downloadQuality = 'Original';

  List<DownloadTask> get queue => List.unmodifiable(_queue);
  Map<String, DownloadTask> get tasks => Map.unmodifiable(_tasks);
  bool get isProcessing => _isProcessing;

  /// Number of chapters to keep before auto-deleting older ones (e.g.
  /// "After 5 chapters" → 5). 0 means disabled.
  int get autoDeleteThreshold {
    final m = RegExp(r'(\d+)').firstMatch(autoDeleteAfter);
    return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
  }

  /// Reference to source provider (set from outside after construction).
  SourceProvider? sourceProvider;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    autoDownload = prefs.getBool('dl_auto') ?? false;
    wifiOnly = prefs.getBool('dl_wifi_only') ?? true;
    onlyWhenCharging = prefs.getBool('dl_only_charging') ?? false;
    downloadWhileReading = prefs.getBool('dl_while_reading') ?? false;
    deleteAfterRead = prefs.getBool('dl_delete_after_read') ?? false;
    removeBookmarked = prefs.getBool('dl_remove_bookmarked') ?? false;
    autoDeleteAfter = prefs.getString('dl_auto_delete') ?? 'Disabled';
    saveAsCbz = prefs.getBool('dl_save_cbz') ?? false;
    saveAsPdf = prefs.getBool('dl_save_pdf') ?? false;
    simultaneousDownloads = prefs.getString('dl_simultaneous') ?? '2';
    downloadQuality = prefs.getString('dl_quality') ?? 'Original';
    _maxConcurrent = int.tryParse(simultaneousDownloads) ?? 2;
    _downloadedChapters.addAll(prefs.getStringList('downloaded_chapters') ?? []);
  }

  Future<void> _saveDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('downloaded_chapters', _downloadedChapters.toList());
  }

  Future<void> saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    switch (key) {
      case 'dl_auto':
        autoDownload = value;
        break;
      case 'dl_wifi_only':
        wifiOnly = value;
        break;
      case 'dl_only_charging':
        onlyWhenCharging = value;
        break;
      case 'dl_while_reading':
        downloadWhileReading = value;
        break;
      case 'dl_delete_after_read':
        deleteAfterRead = value;
        break;
      case 'dl_remove_bookmarked':
        removeBookmarked = value;
        break;
      case 'dl_save_cbz':
        saveAsCbz = value;
        // CBZ and PDF export are mutually exclusive.
        if (value && saveAsPdf) {
          saveAsPdf = false;
          await prefs.setBool('dl_save_pdf', false);
        }
        break;
      case 'dl_save_pdf':
        saveAsPdf = value;
        if (value && saveAsCbz) {
          saveAsCbz = false;
          await prefs.setBool('dl_save_cbz', false);
        }
        break;
    }
    notifyListeners();
  }

  /// String-valued setting persistence (simultaneous downloads, quality,
  /// auto-delete threshold).
  Future<void> saveStringSetting(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    switch (key) {
      case 'dl_simultaneous':
        simultaneousDownloads = value;
        // Apply new concurrency immediately. New tasks pick it up; in-flight
        // ones complete on their own.
        _maxConcurrent = int.tryParse(value) ?? 2;
        // Kick the queue in case the new limit is higher than current active.
        _processQueue();
        break;
      case 'dl_quality':
        downloadQuality = value;
        break;
      case 'dl_auto_delete':
        autoDeleteAfter = value;
        break;
    }
    notifyListeners();
  }

  /// Check if a chapter is downloaded.
  bool isDownloaded(String sourceId, String chapterUrl) {
    return _downloadedChapters.contains('${sourceId}_$chapterUrl');
  }

  /// Get active task for a chapter (if downloading/queued).
  DownloadTask? getTask(String sourceId, String chapterUrl) {
    return _tasks['${sourceId}_$chapterUrl'];
  }

  /// Queue a single chapter for download.
  void enqueueChapter({
    required String sourceId,
    required String mangaUrl,
    required String mangaTitle,
    required String chapterUrl,
    required String chapterName,
    bool isVault = false,
  }) {
    final key = '${sourceId}_$chapterUrl';
    if (_tasks.containsKey(key) || _downloadedChapters.contains(key)) return;

    final task = DownloadTask(
      sourceId: sourceId,
      mangaUrl: mangaUrl,
      mangaTitle: mangaTitle,
      chapterUrl: chapterUrl,
      chapterName: chapterName,
      isVault: isVault,
    );
    _tasks[key] = task;
    _queue.add(task);
    notifyListeners();
    _processQueue();
  }

  /// Queue an anime episode for download.
  void enqueueEpisode({
    required String sourceId,
    required String animeUrl,
    required String animeTitle,
    required String episodeUrl,
    required String episodeName,
  }) {
    final key = '${sourceId}_$episodeUrl';
    if (_tasks.containsKey(key) || _downloadedChapters.contains(key)) return;

    final task = DownloadTask(
      sourceId: sourceId,
      mangaUrl: animeUrl,
      mangaTitle: animeTitle,
      chapterUrl: episodeUrl,
      chapterName: episodeName,
      isAnime: true,
    );
    _tasks[key] = task;
    _queue.add(task);
    notifyListeners();
    _processQueue();
  }

  /// Queue multiple chapters.
  void enqueueChapters(List<Map<String, String>> chapters) {
    for (final ch in chapters) {
      enqueueChapter(
        sourceId: ch['sourceId']!,
        mangaUrl: ch['mangaUrl']!,
        mangaTitle: ch['mangaTitle']!,
        chapterUrl: ch['chapterUrl']!,
        chapterName: ch['chapterName']!,
      );
    }
  }

  /// Cancel a download task.
  void cancelTask(String sourceId, String chapterUrl) {
    final key = '${sourceId}_$chapterUrl';
    final task = _tasks[key];
    if (task != null) {
      task.status = DownloadStatus.cancelled;
      _queue.removeWhere((t) => t.key == key);
      _tasks.remove(key);
      notifyListeners();
    }
  }

  /// Cancel all queued/active downloads.
  void cancelAll() {
    for (final task in _tasks.values) {
      task.status = DownloadStatus.cancelled;
    }
    _queue.clear();
    _tasks.clear();
    _isProcessing = false;
    _activeCount = 0;
    notifyListeners();
  }

  /// Delete a downloaded chapter from disk.
  Future<void> deleteDownload(
      String sourceId, String mangaTitle, String chapterName, String chapterUrl) async {
    await _downloadService.deleteChapter(sourceId, mangaTitle, chapterName);
    _downloadedChapters.remove('${sourceId}_$chapterUrl');
    await _saveDownloaded();
    notifyListeners();
  }

  /// Process the download queue.
  Future<void> _processQueue() async {
    if (_isProcessing && _activeCount >= _maxConcurrent) return;
    _isProcessing = true;

    while (_queue.isNotEmpty && _activeCount < _maxConcurrent) {
      final task = _queue.removeAt(0);
      if (task.status == DownloadStatus.cancelled) continue;
      _activeCount++;
      _downloadChapter(task); // fire and forget, managed by _activeCount
    }
  }

  Future<void> _downloadChapter(DownloadTask task) async {
    task.status = DownloadStatus.downloading;
    notifyListeners();

    try {
      final installed = sourceProvider?.getInstalledSource(task.sourceId);
      if (installed == null) throw Exception('Source not installed');

      if (task.isAnime) {
        await _downloadEpisode(task, installed);
      } else {
        await _downloadMangaChapter(task, installed);
      }
    } catch (e) {
      debugPrint('[Download] Error downloading ${task.chapterName}: $e');
      task.status = DownloadStatus.failed;
    }

    _activeCount--;
    _tasks.remove(task.key);
    notifyListeners();

    // Process next in queue
    if (_queue.isNotEmpty) _processQueue();
    if (_activeCount == 0) _isProcessing = false;
  }

  Future<void> _downloadMangaChapter(DownloadTask task, dynamic installed) async {
    final pages = await withExtensionService(
      installed.source, installed.sourceCode,
      (service) => service.getPageList(task.chapterUrl),
    );

    final imageUrls = pages.map((p) => p.url).toList();
    task.total = imageUrls.length;
    notifyListeners();

    Map<String, String> headers = {};
    try {
      headers = await withExtensionService(
        installed.source, installed.sourceCode,
        (service) async => service.getHeaders(),
      );
    } catch (_) {}

    final success = await _downloadService.downloadChapter(
      sourceId: task.sourceId,
      mangaTitle: task.mangaTitle,
      chapterName: task.chapterName,
      imageUrls: imageUrls,
      headers: headers,
      isVault: task.isVault,
      onProgress: (completed, total) {
        task.completed = completed;
        task.total = total;
        notifyListeners();
      },
    );

    if (task.status == DownloadStatus.cancelled) return;

    if (success) {
      if (saveAsCbz) {
        await _downloadService.convertToCbz(
          sourceId: task.sourceId,
          mangaTitle: task.mangaTitle,
          chapterName: task.chapterName,
          isVault: task.isVault,
        );
      } else if (saveAsPdf) {
        await _downloadService.convertToPdf(
          sourceId: task.sourceId,
          mangaTitle: task.mangaTitle,
          chapterName: task.chapterName,
          isVault: task.isVault,
        );
      }
      task.status = DownloadStatus.completed;
      _downloadedChapters.add(task.key);
      await _saveDownloaded();
    } else {
      task.status = DownloadStatus.failed;
    }
  }

  Future<void> _downloadEpisode(DownloadTask task, dynamic installed) async {
    final videos = await withExtensionService(
      installed.source, installed.sourceCode,
      (service) => service.getVideoList(task.chapterUrl),
    );

    if (videos.isEmpty) {
      task.status = DownloadStatus.failed;
      return;
    }

    // Pick quality: prefer setting match, fall back to first
    final video = _pickVideo(videos);

    task.total = 1;
    notifyListeners();

    final success = await _downloadService.downloadEpisode(
      sourceId: task.sourceId,
      animeTitle: task.mangaTitle,
      episodeName: task.chapterName,
      videoUrl: video.url,
      headers: video.headers ?? {},
      onProgress: (received, total) {
        task.completed = received;
        task.total = total > 0 ? total : 1;
        notifyListeners();
      },
    );

    if (task.status == DownloadStatus.cancelled) return;

    if (success) {
      task.status = DownloadStatus.completed;
      _downloadedChapters.add(task.key);
      await _saveDownloaded();
    } else {
      task.status = DownloadStatus.failed;
    }
  }

  /// Pick the best video from a list based on the downloadQuality setting.
  dynamic _pickVideo(List<dynamic> videos) {
    if (videos.length == 1) return videos.first;
    // Try to match quality label (e.g. "1080p", "720p")
    final pref = downloadQuality.toLowerCase();
    for (final v in videos) {
      if (v.quality.toLowerCase().contains(pref)) return v;
    }
    // Default: highest quality (assume list is ordered best-first, or pick last
    // which is often highest res on anime sources)
    return videos.first;
  }

  /// Get total download size.
  Future<int> getTotalSize({bool? isVault}) => _downloadService.getTotalSize(isVault: isVault);

  /// Get local pages for a downloaded chapter.
  Future<List<String>> getLocalPages(
      String sourceId, String mangaTitle, String chapterName) {
    return _downloadService.getLocalPages(sourceId, mangaTitle, chapterName);
  }
}
