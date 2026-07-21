import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/manga_model.dart';
import '../models/chapter_model.dart';
import '../models/category_model.dart';

/// A backup file on disk (native `.fxbackup` or Tachiyomi/Mihon `.tachibk`).
class BackupFile {
  final String path;
  final String name; // display, e.g. 20260720-23:12
  final DateTime date;
  final int sizeBytes;
  final bool isTachiyomi;
  final bool isAuto;
  const BackupFile(this.path, this.name, this.date, this.sizeBytes,
      this.isTachiyomi, this.isAuto);
}

enum BackupFrequency { off, daily, weekly, monthly }

/// Create/restore library backups — a native gzipped-JSON format, plus
/// read/write of the Tachiyomi/Mihon gzipped-protobuf `.tachibk` format for
/// cross-app migration. Also manages automatic scheduled backups.
class BackupService {
  static const _repoPrefsKey = 'extension_repo_urls';
  static const _freqKey = 'backup_frequency';
  static const _lastAutoKey = 'backup_last_auto';
  static const _maxAutoKept = 8;

  // ── boxes (already opened by the library/tracking services) ──
  Box<LibraryManga> get _mangaBox => Hive.box<LibraryManga>('library_manga');
  Box<LibraryChapter> get _chapterBox =>
      Hive.box<LibraryChapter>('library_chapters');
  Box<Category> get _categoryBox => Hive.box<Category>('library_categories');
  Box? get _trackingBox =>
      Hive.isBoxOpen('tracking') ? Hive.box('tracking') : null;

  Future<Directory> _backupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/Foxlations/backups');
    await dir.create(recursive: true);
    return dir;
  }

  String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}';
  }

  String _displayName(String fileStamp) {
    // 20260720-2312 -> 20260720-23:12
    final m = RegExp(r'(\d{8})-(\d{2})(\d{2})').firstMatch(fileStamp);
    return m != null ? '${m.group(1)}-${m.group(2)}:${m.group(3)}' : fileStamp;
  }

  // ─────────────────────────── native format ───────────────────────────

  Map<String, dynamic> _mangaToMap(LibraryManga m) => {
        'sourceId': m.sourceId,
        'url': m.url,
        'title': m.title,
        'coverUrl': m.coverUrl,
        'author': m.author,
        'description': m.description,
        'genres': m.genres,
        'status': m.status,
        'addedAt': m.addedAt.millisecondsSinceEpoch,
        'lastReadAt': m.lastReadAt?.millisecondsSinceEpoch,
        'lastReadChapterUrl': m.lastReadChapterUrl,
        'lastReadPage': m.lastReadPage,
        'totalChapters': m.totalChapters,
        'readChapters': m.readChapters,
        'categories': m.categories,
      };

  LibraryManga _mangaFromMap(Map m) => LibraryManga(
        sourceId: (m['sourceId'] ?? '').toString(),
        url: (m['url'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        coverUrl: (m['coverUrl'] ?? '').toString(),
        author: m['author'] as String?,
        description: m['description'] as String?,
        genres: (m['genres'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        status: (m['status'] ?? 'unknown').toString(),
        addedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['addedAt'] as num?)?.toInt() ?? 0),
        lastReadAt: m['lastReadAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch((m['lastReadAt'] as num).toInt())
            : null,
        lastReadChapterUrl: m['lastReadChapterUrl'] as String?,
        lastReadPage: (m['lastReadPage'] as num?)?.toInt() ?? 0,
        totalChapters: (m['totalChapters'] as num?)?.toInt() ?? 0,
        readChapters: (m['readChapters'] as num?)?.toInt() ?? 0,
        categories:
            (m['categories'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );

  Map<String, dynamic> _chapterToMap(LibraryChapter c) => {
        'sourceId': c.sourceId,
        'mangaUrl': c.mangaUrl,
        'chapterUrl': c.chapterUrl,
        'title': c.title,
        'chapterNumber': c.chapterNumber,
        'scanlator': c.scanlator,
        'dateUpload': c.dateUpload,
        'isRead': c.isRead,
        'lastPageRead': c.lastPageRead,
        'readAt': c.readAt?.millisecondsSinceEpoch,
        'sourceIndex': c.sourceIndex,
      };

  LibraryChapter _chapterFromMap(Map c) => LibraryChapter(
        sourceId: (c['sourceId'] ?? '').toString(),
        mangaUrl: (c['mangaUrl'] ?? '').toString(),
        chapterUrl: (c['chapterUrl'] ?? '').toString(),
        title: (c['title'] ?? '').toString(),
        chapterNumber: (c['chapterNumber'] as num?)?.toDouble(),
        scanlator: c['scanlator'] as String?,
        dateUpload: c['dateUpload'] as String?,
        isRead: c['isRead'] as bool? ?? false,
        lastPageRead: (c['lastPageRead'] as num?)?.toInt() ?? 0,
        readAt: c['readAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch((c['readAt'] as num).toInt())
            : null,
        sourceIndex: (c['sourceIndex'] as num?)?.toInt(),
      );

  /// Create a native backup. Returns the file path.
  Future<String> createBackup({DateTime? now, bool auto = false}) async {
    final ts = now ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final tracking = <String, dynamic>{};
    final tb = _trackingBox;
    if (tb != null) {
      for (final k in tb.keys) {
        if (k is String && k.startsWith('bind_')) tracking[k] = tb.get(k);
      }
    }
    final data = {
      'format': 'foxlations-native',
      'version': 1,
      'createdAt': ts.millisecondsSinceEpoch,
      'manga': _mangaBox.values.map(_mangaToMap).toList(),
      'chapters': _chapterBox.values.map(_chapterToMap).toList(),
      'categories':
          _categoryBox.values.map((c) => {'name': c.name, 'order': c.order}).toList(),
      'repos': prefs.getStringList(_repoPrefsKey) ?? const [],
      'tracking': tracking,
    };
    final gz = GZipEncoder().encode(utf8.encode(jsonEncode(data)));
    final dir = await _backupDir();
    final file = File(
        '${dir.path}/foxlations-${_stamp(ts)}${auto ? '-auto' : ''}.fxbackup');
    await file.writeAsBytes(gz);
    return file.path;
  }

  /// Restore a native backup (merges into the current library).
  Future<void> restoreBackup(String path) async {
    final bytes = await File(path).readAsBytes();
    final json = utf8.decode(GZipDecoder().decodeBytes(bytes));
    final data = jsonDecode(json) as Map<String, dynamic>;

    for (final m in (data['manga'] as List? ?? const [])) {
      final manga = _mangaFromMap(m as Map);
      await _mangaBox.put(manga.uniqueKey, manga);
    }
    for (final c in (data['chapters'] as List? ?? const [])) {
      final ch = _chapterFromMap(c as Map);
      await _chapterBox.put(ch.uniqueKey, ch);
    }
    final existingCats = _categoryBox.values.map((c) => c.name).toSet();
    for (final c in (data['categories'] as List? ?? const [])) {
      final name = (c as Map)['name']?.toString() ?? '';
      if (name.isNotEmpty && !existingCats.contains(name)) {
        await _categoryBox.add(
            Category(name: name, order: (c['order'] as num?)?.toInt() ?? 0));
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final repos = (prefs.getStringList(_repoPrefsKey) ?? []).toSet();
    for (final r in (data['repos'] as List? ?? const [])) {
      repos.add(r.toString());
    }
    await prefs.setStringList(_repoPrefsKey, repos.toList());
    final tb = _trackingBox;
    if (tb != null) {
      final tr = data['tracking'] as Map?;
      if (tr != null) {
        for (final entry in tr.entries) {
          await tb.put(entry.key, entry.value);
        }
      }
    }
  }

  // ───────────────────── Tachiyomi / Mihon (.tachibk) ─────────────────────

  int _sourceIdHash(String s) {
    // Stable positive 63-bit hash of a Foxlations source id, used as the
    // Tachiyomi int64 `source`. Won't match a foreign app's extension ids, but
    // preserves the data and round-trips within Foxlations (via backupSources).
    var h = 1125899906842597; // prime
    for (final c in s.codeUnits) {
      h = (31 * h + c) & 0x7FFFFFFFFFFFFFFF;
    }
    return h;
  }

  /// Export the library to a Tachiyomi/Mihon-compatible `.tachibk`.
  Future<String> createTachiyomiBackup({DateTime? now}) async {
    final ts = now ?? DateTime.now();
    final cats = _categoryBox.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final catOrder = {for (var i = 0; i < cats.length; i++) cats[i].name: i};
    final sources = <String, int>{}; // foxlations sourceId -> hash

    final root = _ProtoWriter();
    for (final m in _mangaBox.values) {
      sources[m.sourceId] = _sourceIdHash(m.sourceId);
      final bm = _ProtoWriter();
      bm.varint(1, sources[m.sourceId]!);
      bm.string(2, m.url);
      bm.string(3, m.title);
      if (m.author != null) bm.string(5, m.author!);
      if (m.description != null) bm.string(6, m.description!);
      for (final g in m.genres) bm.string(7, g);
      bm.varint(8, _statusToTachi(m.status));
      bm.string(9, m.coverUrl);
      bm.varint(13, m.addedAt.millisecondsSinceEpoch);
      // chapters
      final chapters = _chapterBox.values
          .where((c) => c.sourceId == m.sourceId && c.mangaUrl == m.url)
          .toList();
      for (final c in chapters) {
        final bc = _ProtoWriter();
        bc.string(1, c.chapterUrl);
        bc.string(2, c.title);
        if (c.scanlator != null) bc.string(3, c.scanlator!);
        bc.boolean(4, c.isRead);
        bc.varint(6, c.lastPageRead);
        if (c.chapterNumber != null) bc.floatUnconditional(9, c.chapterNumber!);
        if (c.sourceIndex != null) bc.varintUnconditional(10, c.sourceIndex!);
        bm.message(16, bc.toBytes());
      }
      // categories (by order index — index 0 is valid, so write unconditionally)
      for (final cat in m.categories) {
        final idx = catOrder[cat];
        if (idx != null) bm.varintUnconditional(17, idx);
      }
      bm.boolean(100, true); // favorite
      root.message(1, bm.toBytes());
    }
    // categories
    for (var i = 0; i < cats.length; i++) {
      final bc = _ProtoWriter();
      bc.string(1, cats[i].name);
      bc.varint(2, i);
      root.message(2, bc.toBytes());
    }
    // sources (name = foxlations sourceId, so our own restores recover it)
    for (final e in sources.entries) {
      final bs = _ProtoWriter();
      bs.varint(1, e.value);
      bs.string(2, e.key);
      root.message(101, bs.toBytes());
    }

    final gz = GZipEncoder().encode(root.toBytes());
    final dir = await _backupDir();
    final file = File('${dir.path}/foxlations-${_stamp(ts)}.tachibk');
    await file.writeAsBytes(gz);
    return file.path;
  }

  /// Restore from a Tachiyomi/Mihon `.tachibk`. Matches each manga's source to
  /// an installed Foxlations source by the backup's source name when possible.
  /// Returns how many manga were imported.
  Future<int> restoreTachiyomiBackup(String path,
      {List<String> installedSourceIds = const []}) async {
    final bytes = await File(path).readAsBytes();
    final data = unwrapBackupBytes(bytes);
    final r = _ProtoReader(data);

    final sourceNames = <int, String>{}; // source int64 -> name
    final mangaMsgs = <Uint8List>[];
    final categoryNames = <int, String>{};

    while (r.hasMore) {
      final t = r.readTag();
      switch (t.field) {
        case 1: // backupManga
          mangaMsgs.add(r.readBytes());
          break;
        case 2: // backupCategory
          final cr = _ProtoReader(r.readBytes());
          String name = '';
          int order = 0;
          while (cr.hasMore) {
            final ct = cr.readTag();
            if (ct.field == 1 && ct.wire == 2) {
              name = cr.readStringValue();
            } else if (ct.field == 2 && ct.wire == 0) {
              order = cr.readVarint();
            } else {
              cr.skip(ct.wire);
            }
          }
          if (name.isNotEmpty) categoryNames[order] = name;
          break;
        case 101: // backupSource
          final sr = _ProtoReader(r.readBytes());
          int id = 0;
          String name = '';
          while (sr.hasMore) {
            final st = sr.readTag();
            if (st.field == 1 && st.wire == 0) {
              id = sr.readVarint();
            } else if (st.field == 2 && st.wire == 2) {
              name = sr.readStringValue();
            } else {
              sr.skip(st.wire);
            }
          }
          sourceNames[id] = name;
          break;
        default:
          r.skip(t.wire);
      }
    }

    // Restore categories.
    final existingCats = _categoryBox.values.map((c) => c.name).toSet();
    for (final e in categoryNames.entries) {
      if (!existingCats.contains(e.value)) {
        await _categoryBox.add(Category(name: e.value, order: e.key));
      }
    }
    final orderToCat = categoryNames;

    var imported = 0;
    for (final mm in mangaMsgs) {
      final mr = _ProtoReader(mm);
      int source = 0;
      String url = '', title = '', author = '', description = '', cover = '';
      final genres = <String>[];
      final catIdx = <int>[];
      int status = 0;
      int dateAdded = 0;
      final chapters = <LibraryChapter>[];
      while (mr.hasMore) {
        final t = mr.readTag();
        switch (t.field) {
          case 1:
            source = mr.readVarint();
            break;
          case 2:
            url = mr.readStringValue();
            break;
          case 3:
            title = mr.readStringValue();
            break;
          case 5:
            author = mr.readStringValue();
            break;
          case 6:
            description = mr.readStringValue();
            break;
          case 7:
            genres.add(mr.readStringValue());
            break;
          case 8:
            status = mr.readVarint();
            break;
          case 9:
            cover = mr.readStringValue();
            break;
          case 13:
            dateAdded = mr.readVarint();
            break;
          case 16:
            chapters.add(_readTachiChapter(mr.readBytes()));
            break;
          case 17:
            catIdx.add(mr.readVarint());
            break;
          default:
            mr.skip(t.wire);
        }
      }
      if (url.isEmpty || title.isEmpty) continue;

      // Map source int64 -> a Foxlations source id.
      final backupName = sourceNames[source] ?? '';
      final sourceId = _resolveSourceId(backupName, installedSourceIds);

      final manga = LibraryManga(
        sourceId: sourceId,
        url: url,
        title: title,
        coverUrl: cover,
        author: author.isEmpty ? null : author,
        description: description.isEmpty ? null : description,
        genres: genres,
        status: _statusFromTachi(status),
        addedAt: dateAdded > 0
            ? DateTime.fromMillisecondsSinceEpoch(dateAdded)
            : DateTime.now(),
        categories: catIdx
            .map((i) => orderToCat[i])
            .whereType<String>()
            .toList(),
        totalChapters: chapters.length,
        readChapters: chapters.where((c) => c.isRead).length,
      );
      await _mangaBox.put(manga.uniqueKey, manga);
      for (final c in chapters) {
        c.sourceId = sourceId;
        c.mangaUrl = url;
        await _chapterBox.put(c.uniqueKey, c);
      }
      imported++;
    }
    return imported;
  }

  LibraryChapter _readTachiChapter(Uint8List bytes) {
    final r = _ProtoReader(bytes);
    String url = '', name = '', scanlator = '';
    bool read = false;
    int lastPage = 0, dateUpload = 0;
    double number = -1;
    int sourceOrder = 0;
    while (r.hasMore) {
      final t = r.readTag();
      switch (t.field) {
        case 1:
          url = r.readStringValue();
          break;
        case 2:
          name = r.readStringValue();
          break;
        case 3:
          scanlator = r.readStringValue();
          break;
        case 4:
          read = r.readVarint() != 0;
          break;
        case 6:
          lastPage = r.readVarint();
          break;
        case 8:
          dateUpload = r.readVarint();
          break;
        case 9:
          number = r.readFloat();
          break;
        case 10:
          sourceOrder = r.readVarint();
          break;
        default:
          r.skip(t.wire);
      }
    }
    return LibraryChapter(
      sourceId: '',
      mangaUrl: '',
      chapterUrl: url,
      title: name,
      scanlator: scanlator.isEmpty ? null : scanlator,
      isRead: read,
      lastPageRead: lastPage,
      chapterNumber: number >= 0 ? number : null,
      dateUpload: dateUpload > 0 ? dateUpload.toString() : null,
      sourceIndex: sourceOrder,
    );
  }

  String _resolveSourceId(String backupName, List<String> installed) {
    if (backupName.isEmpty) return backupName;
    // Our own exports store the Foxlations sourceId as the name.
    if (installed.contains(backupName)) return backupName;
    // Otherwise match by loose name similarity.
    final low = backupName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final id in installed) {
      final n = id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (n == low || n.contains(low) || low.contains(n)) return id;
    }
    return backupName; // keep it; manga imported but may not open
  }

  int _statusToTachi(String s) {
    switch (s) {
      case 'ongoing':
        return 1;
      case 'completed':
        return 2;
      case 'hiatus':
        return 6;
      case 'canceled':
      case 'cancelled':
        return 5;
      default:
        return 0;
    }
  }

  String _statusFromTachi(int s) {
    switch (s) {
      case 1:
      case 4: // publishing finished
        return 'ongoing';
      case 2:
        return 'completed';
      case 5:
        return 'canceled';
      case 6:
        return 'hiatus';
      default:
        return 'unknown';
    }
  }

  // ───────────────────────── listing / auto ─────────────────────────

  Future<List<BackupFile>> listBackups() async {
    final dir = await _backupDir();
    final files = <BackupFile>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final base = e.uri.pathSegments.last;
      if (!base.endsWith('.fxbackup') && !base.endsWith('.tachibk')) continue;
      final stat = await e.stat();
      final stampMatch = RegExp(r'(\d{8}-\d{4})').firstMatch(base);
      files.add(BackupFile(
        e.path,
        stampMatch != null ? _displayName(stampMatch.group(1)!) : base,
        stat.modified,
        stat.size,
        base.endsWith('.tachibk'),
        base.contains('-auto'),
      ));
    }
    files.sort((a, b) => b.date.compareTo(a.date));
    return files;
  }

  Future<void> deleteBackup(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  Future<BackupFrequency> getFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_freqKey) ?? 'off';
    return BackupFrequency.values
        .firstWhere((f) => f.name == v, orElse: () => BackupFrequency.off);
  }

  Future<void> setFrequency(BackupFrequency f) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_freqKey, f.name);
  }

  Duration? _interval(BackupFrequency f) {
    switch (f) {
      case BackupFrequency.daily:
        return const Duration(days: 1);
      case BackupFrequency.weekly:
        return const Duration(days: 7);
      case BackupFrequency.monthly:
        return const Duration(days: 30);
      case BackupFrequency.off:
        return null;
    }
  }

  /// Run an automatic backup if the configured interval has elapsed. Safe to
  /// call on every app launch — no-ops when off or not yet due. Prunes old
  /// automatic backups to [_maxAutoKept].
  Future<void> maybeRunAuto() async {
    final freq = await getFrequency();
    final interval = _interval(freq);
    if (interval == null) return;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastAutoKey) ?? 0;
    final now = DateTime.now();
    if (now.millisecondsSinceEpoch - last < interval.inMilliseconds) return;
    try {
      await createBackup(now: now, auto: true);
      await prefs.setInt(_lastAutoKey, now.millisecondsSinceEpoch);
      await _pruneAuto();
    } catch (_) {}
  }

  Future<void> _pruneAuto() async {
    final autos = (await listBackups()).where((b) => b.isAuto).toList();
    if (autos.length <= _maxAutoKept) return;
    for (final b in autos.skip(_maxAutoKept)) {
      await deleteBackup(b.path);
    }
  }
}

// ─────────────────────── minimal protobuf codec ───────────────────────

class _ProtoWriter {
  final BytesBuilder _b = BytesBuilder();

  void _rawVarint(int value) {
    var v = value;
    while (true) {
      if ((v & ~0x7F) == 0) {
        _b.addByte(v);
        return;
      }
      _b.addByte((v & 0x7F) | 0x80);
      v = v >>> 7;
    }
  }

  void _tag(int field, int wire) => _rawVarint((field << 3) | wire);

  void varint(int field, int value) {
    if (value == 0) return;
    _tag(field, 0);
    _rawVarint(value);
  }

  /// Always write, even for 0 — required for repeated fields / index values
  /// where 0 is meaningful (e.g. category index 0, chapter source order 0).
  void varintUnconditional(int field, int value) {
    _tag(field, 0);
    _rawVarint(value);
  }

  void floatUnconditional(int field, double value) {
    _tag(field, 5);
    final bd = ByteData(4)..setFloat32(0, value, Endian.little);
    _b.add(bd.buffer.asUint8List());
  }

  void boolean(int field, bool value) {
    if (!value) return;
    _tag(field, 0);
    _rawVarint(1);
  }

  void string(int field, String value) {
    if (value.isEmpty) return;
    final bytes = utf8.encode(value);
    _tag(field, 2);
    _rawVarint(bytes.length);
    _b.add(bytes);
  }

  void message(int field, List<int> msg) {
    _tag(field, 2);
    _rawVarint(msg.length);
    _b.add(msg);
  }

  void float(int field, double value) {
    if (value == 0) return;
    _tag(field, 5);
    final bd = ByteData(4)..setFloat32(0, value, Endian.little);
    _b.add(bd.buffer.asUint8List());
  }

  Uint8List toBytes() => _b.toBytes();
}

/// Unwrap a backup file down to raw protobuf bytes.
///
/// The extension is not trusted — different apps wrap the same payload
/// differently and users rename files:
///   * Tachiyomi/Mihon `.tachibk` / `.proto.gz` → gzip (magic `1f 8b`)
///   * Tachimanga `.tmb`                        → ZIP  (magic `50 4b`)
///   * already-extracted payloads               → raw protobuf
///
/// Sniffing the magic bytes means a `.tmb` renamed to `.tachibk` (or the
/// reverse) still restores, instead of dying deep inside the proto parser with
/// an unhelpful RangeError.
Uint8List unwrapBackupBytes(Uint8List raw, {int depth = 0}) {
  if (raw.length >= 2 && raw[0] == 0x1F && raw[1] == 0x8B) {
    return Uint8List.fromList(GZipDecoder().decodeBytes(raw));
  }

  if (raw.length >= 4 && raw[0] == 0x50 && raw[1] == 0x4B) {
    if (depth > 1) {
      throw const FormatException('Backup archive is nested too deeply.');
    }
    final archive = ZipDecoder().decodeBytes(raw);
    final files = archive.files.where((f) => f.isFile).toList();
    if (files.isEmpty) {
      throw const FormatException('Backup archive is empty.');
    }
    // Prefer an entry that names itself a backup; otherwise the largest file,
    // which in practice is the library payload rather than a cover thumbnail.
    bool looksLikeBackup(String n) {
      final l = n.toLowerCase();
      return l.endsWith('.proto.gz') ||
          l.endsWith('.tachibk') ||
          l.endsWith('.proto') ||
          l.contains('backup');
    }

    final candidates = files.where((f) => looksLikeBackup(f.name)).toList();
    final chosen = (candidates.isNotEmpty ? candidates : files)
      ..sort((a, b) => b.size.compareTo(a.size));
    return unwrapBackupBytes(chosen.first.content, depth: depth + 1);
  }

  // No known container — assume it is already raw protobuf.
  return raw;
}

/// Minimal protobuf reader.
///
/// Every read is bounds-checked. Previously any surprise in the stream — an
/// unexpected wire type, a field written by a newer Tachiyomi fork, a container
/// we mis-detected — walked straight off the end of the buffer and surfaced as
/// a bare `RangeError (length): Not in inclusive range 0..17: 18`, which says
/// nothing about what actually went wrong. Now it throws a [FormatException]
/// naming the offset, so a bad backup produces a message a user can act on.
class _ProtoReader {
  final Uint8List _d;
  int _pos = 0;
  _ProtoReader(this._d);

  bool get hasMore => _pos < _d.length;
  int get _remaining => _d.length - _pos;

  Never _bad(String what) => throw FormatException(
      'Malformed backup: $what (at byte $_pos of ${_d.length})');

  int readVarint() {
    int result = 0, shift = 0;
    while (true) {
      if (_pos >= _d.length) _bad('truncated varint');
      final b = _d[_pos++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
      if (shift > 63) _bad('varint longer than 10 bytes');
    }
    return result;
  }

  ({int field, int wire}) readTag() {
    final t = readVarint();
    return (field: t >> 3, wire: t & 7);
  }

  Uint8List readBytes() {
    final len = readVarint();
    if (len < 0 || len > _remaining) {
      _bad('length-delimited field claims $len bytes, $_remaining remain');
    }
    final b = Uint8List.sublistView(_d, _pos, _pos + len);
    _pos += len;
    return b;
  }

  String readStringValue() {
    // Tolerate mildly invalid UTF-8 rather than aborting a whole restore.
    return utf8.decode(readBytes(), allowMalformed: true);
  }

  double readFloat() {
    if (_remaining < 4) _bad('truncated 32-bit value');
    final bd = ByteData.sublistView(_d, _pos, _pos + 4);
    _pos += 4;
    return bd.getFloat32(0, Endian.little);
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        readVarint();
        break;
      case 1:
        if (_remaining < 8) _bad('truncated 64-bit value');
        _pos += 8;
        break;
      case 2:
        final n = readVarint();
        if (n < 0 || n > _remaining) {
          _bad('nested field claims $n bytes, $_remaining remain');
        }
        _pos += n;
        break;
      case 5:
        if (_remaining < 4) _bad('truncated 32-bit value');
        _pos += 4;
        break;
      default:
        // Wire types 3/4 (deprecated groups) and 6/7 are not valid here.
        _bad('unsupported wire type $wire');
    }
  }
}
