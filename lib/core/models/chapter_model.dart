import 'package:hive/hive.dart';

class LibraryChapter extends HiveObject {
  String sourceId;
  String mangaUrl;
  String chapterUrl;
  String title;
  double? chapterNumber;
  String? scanlator;
  String? dateUpload;
  bool isRead;
  int lastPageRead;
  DateTime? readAt;
  /// Position in the source's chapter list at cache time. Used by
  /// LibraryService to return cached chapters in the same order the source
  /// originally returned them, instead of Hive's key insertion order.
  /// Null for chapters cached before this field existed.
  int? sourceIndex;

  LibraryChapter({
    required this.sourceId,
    required this.mangaUrl,
    required this.chapterUrl,
    required this.title,
    this.chapterNumber,
    this.scanlator,
    this.dateUpload,
    this.isRead = false,
    this.lastPageRead = 0,
    this.readAt,
    this.sourceIndex,
  });

  String get uniqueKey => '${sourceId}_$chapterUrl';
}

class LibraryChapterAdapter extends TypeAdapter<LibraryChapter> {
  @override
  final int typeId = 1;

  @override
  LibraryChapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return LibraryChapter(
      sourceId: fields[0] as String,
      mangaUrl: fields[1] as String,
      chapterUrl: fields[2] as String,
      title: fields[3] as String,
      chapterNumber: fields[4] as double?,
      scanlator: fields[5] as String?,
      dateUpload: fields[6] as String?,
      isRead: fields[7] as bool? ?? false,
      lastPageRead: fields[8] as int? ?? 0,
      readAt: fields[9] as DateTime?,
      sourceIndex: fields[10] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, LibraryChapter obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.sourceId)
      ..writeByte(1)
      ..write(obj.mangaUrl)
      ..writeByte(2)
      ..write(obj.chapterUrl)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.chapterNumber)
      ..writeByte(5)
      ..write(obj.scanlator)
      ..writeByte(6)
      ..write(obj.dateUpload)
      ..writeByte(7)
      ..write(obj.isRead)
      ..writeByte(8)
      ..write(obj.lastPageRead)
      ..writeByte(9)
      ..write(obj.readAt)
      ..writeByte(10)
      ..write(obj.sourceIndex);
  }
}
