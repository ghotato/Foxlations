import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel { debug, info, warning, error }

enum LogCategory { repo, extension, network, install, library, general }

class LogEntry {
  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final LogCategory category;
  final String message;
  final String? detail;

  const LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'level': level.name,
        'category': category.name,
        'message': message,
        if (detail != null) 'detail': detail,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      id: json['id'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      level: LogLevel.values.firstWhere(
        (l) => l.name == json['level'],
        orElse: () => LogLevel.info,
      ),
      category: LogCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => LogCategory.general,
      ),
      message: json['message'] as String? ?? '',
      detail: json['detail'] as String?,
    );
  }

  String get levelLabel {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  String get categoryLabel {
    switch (category) {
      case LogCategory.repo:
        return 'REPO';
      case LogCategory.extension:
        return 'EXT';
      case LogCategory.network:
        return 'NET';
      case LogCategory.install:
        return 'INSTALL';
      case LogCategory.library:
        return 'LIB';
      case LogCategory.general:
        return 'GENERAL';
    }
  }
}

/// Singleton logger that stores log entries in memory and persists to SharedPreferences.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const _prefsKey = 'app_debug_logs';
  static const _maxEntries = 500;

  final ValueNotifier<List<LogEntry>> logsNotifier = ValueNotifier([]);
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        logsNotifier.value = list
            .map((e) => LogEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = logsNotifier.value;
      await prefs.setString(
          _prefsKey, jsonEncode(entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> log(
    String message, {
    LogLevel level = LogLevel.info,
    LogCategory category = LogCategory.general,
    String? detail,
  }) async {
    await _ensureLoaded();
    final entry = LogEntry(
      id: '${DateTime.now().millisecondsSinceEpoch}_${logsNotifier.value.length}',
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      detail: detail,
    );

    if (kDebugMode) {
      debugPrint(
          '[${entry.levelLabel}][${entry.categoryLabel}] $message${detail != null ? '\n  -> $detail' : ''}');
    }

    final updated = List<LogEntry>.from(logsNotifier.value)..add(entry);
    if (updated.length > _maxEntries) {
      updated.removeRange(0, updated.length - _maxEntries);
    }
    logsNotifier.value = updated;
    await _persist();
  }

  Future<void> debug(String message,
          {LogCategory category = LogCategory.general, String? detail}) =>
      log(message, level: LogLevel.debug, category: category, detail: detail);

  Future<void> info(String message,
          {LogCategory category = LogCategory.general, String? detail}) =>
      log(message, level: LogLevel.info, category: category, detail: detail);

  Future<void> warning(String message,
          {LogCategory category = LogCategory.general, String? detail}) =>
      log(message, level: LogLevel.warning, category: category, detail: detail);

  Future<void> error(String message,
          {LogCategory category = LogCategory.general, String? detail}) =>
      log(message, level: LogLevel.error, category: category, detail: detail);

  Future<void> clearLogs() async {
    logsNotifier.value = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  List<LogEntry> getFiltered({LogCategory? category, LogLevel? minLevel}) {
    return logsNotifier.value.where((e) {
      if (category != null && e.category != category) return false;
      if (minLevel != null && e.level.index < minLevel.index) return false;
      return true;
    }).toList();
  }
}

/// Convenience shorthand
final logger = AppLogger.instance;
