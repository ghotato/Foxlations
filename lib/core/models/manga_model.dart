import 'package:hive/hive.dart';

class LibraryManga extends HiveObject {
  String sourceId;
  String url;
  String title;
  String coverUrl;
  String? author;
  String? description;
  List<String> genres;
  String status; // ongoing, completed, hiatus, canceled, unknown
  DateTime addedAt;
  DateTime? lastReadAt;
  String? lastReadChapterUrl;
  int lastReadPage;
  int totalChapters;
  int readChapters;
  List<String> categories;

  /// When this entry's chapter list was last fetched from its source.
  /// Nullable because entries saved before this field existed have no value
  /// (Hive returns null for an absent field, so old records still read).
  DateTime? lastChapterFetchAt;

  LibraryManga({
    required this.sourceId,
    required this.url,
    required this.title,
    required this.coverUrl,
    this.author,
    this.description,
    this.genres = const [],
    this.status = 'unknown',
    DateTime? addedAt,
    this.lastReadAt,
    this.lastReadChapterUrl,
    this.lastReadPage = 0,
    this.totalChapters = 0,
    this.readChapters = 0,
    this.categories = const [],
    this.lastChapterFetchAt,
  }) : addedAt = addedAt ?? DateTime.now();

  String get uniqueKey => '${sourceId}_$url';
}

class LibraryMangaAdapter extends TypeAdapter<LibraryManga> {
  @override
  final int typeId = 0;

  @override
  LibraryManga read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return LibraryManga(
      sourceId: fields[0] as String,
      url: fields[1] as String,
      title: fields[2] as String,
      coverUrl: fields[3] as String,
      author: fields[4] as String?,
      description: fields[5] as String?,
      genres: (fields[6] as List?)?.cast<String>() ?? [],
      status: fields[7] as String? ?? 'unknown',
      addedAt: fields[8] as DateTime?,
      lastReadAt: fields[9] as DateTime?,
      lastReadChapterUrl: fields[10] as String?,
      lastReadPage: fields[11] as int? ?? 0,
      totalChapters: fields[12] as int? ?? 0,
      readChapters: fields[13] as int? ?? 0,
      categories: (fields[14] as List?)?.cast<String>() ?? [],
      // Field 15 was added later — absent on older records, hence null-safe.
      lastChapterFetchAt: fields[15] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, LibraryManga obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.sourceId)
      ..writeByte(1)
      ..write(obj.url)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.coverUrl)
      ..writeByte(4)
      ..write(obj.author)
      ..writeByte(5)
      ..write(obj.description)
      ..writeByte(6)
      ..write(obj.genres)
      ..writeByte(7)
      ..write(obj.status)
      ..writeByte(8)
      ..write(obj.addedAt)
      ..writeByte(9)
      ..write(obj.lastReadAt)
      ..writeByte(10)
      ..write(obj.lastReadChapterUrl)
      ..writeByte(11)
      ..write(obj.lastReadPage)
      ..writeByte(12)
      ..write(obj.totalChapters)
      ..writeByte(13)
      ..write(obj.readChapters)
      ..writeByte(14)
      ..write(obj.categories)
      ..writeByte(15)
      ..write(obj.lastChapterFetchAt);
  }
}
