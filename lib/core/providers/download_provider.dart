import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/download_service.dart';
import '../../eval/lib.dart';
import '../providers/source_provider.dart';

/// Tracks download state for a single chapter.
class DownloadTask {
  final String sourceId;
  final String mangaUrl;
  final String mangaTitle;
  final String chapterUrl;
  final String chapterName;
  final bool isVault;
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
  final int _maxConcurrent = 2;
  int _activeCount = 0;

  // Settings
  bool autoDownload = false;
  bool wifiOnly = true;
  bool deleteAfterRead = false;
  bool saveAsCbz = false;

  List<DownloadTask> get queue => List.unmodifiable(_queue);
  Map<String, DownloadTask> get tasks => Map.unmodifiable(_tasks);
  bool get isProcessing => _isProcessing;

  /// Reference to source provider (set from outside after construction).
  SourceProvider? sourceProvider;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    autoDownload = prefs.getBool('dl_auto') ?? false;
    wifiOnly = prefs.getBool('dl_wifi_only') ?? true;
    deleteAfterRead = prefs.getBool('dl_delete_after_read') ?? false;
    saveAsCbz = prefs.getBool('dl_save_cbz') ?? false;
    _downloadedChapters.addAll(prefs.getStringList('downloaded_chapters') ?? []);
  }

  Future<void> _saveDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('downloaded_chapters', _downloadedChapters.toList());
  }

  Future<void> saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (key == 'dl_auto') autoDownload = value;
    if (key == 'dl_wifi_only') wifiOnly = value;
    if (key == 'dl_delete_after_read') deleteAfterRead = value;
    if (key == 'dl_save_cbz') saveAsCbz = value;
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
      // Get page URLs from the source extension
      final installed = sourceProvider?.getInstalledSource(task.sourceId);
      if (installed == null) throw Exception('Source not installed');

      final pages = await withExtensionService(
        installed.source, installed.sourceCode,
        (service) => service.getPageList(task.chapterUrl),
      );

      final imageUrls = pages.map((p) => p.url).toList();
      task.total = imageUrls.length;
      notifyListeners();

      // Get headers from the source
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
        // Convert to CBZ if enabled
        if (saveAsCbz) {
          await _downloadService.convertToCbz(
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

  /// Get total download size.
  Future<int> getTotalSize({bool? isVault}) => _downloadService.getTotalSize(isVault: isVault);

  /// Get local pages for a downloaded chapter.
  Future<List<String>> getLocalPages(
      String sourceId, String mangaTitle, String chapterName) {
    return _downloadService.getLocalPages(sourceId, mangaTitle, chapterName);
  }
}
