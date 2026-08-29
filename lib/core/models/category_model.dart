import 'package:hive/hive.dart';

class Category extends HiveObject {
  String name;
  int order;

  Category({
    required this.name,
    this.order = 0,
  });
}

class CategoryAdapter extends TypeAdapter<Category> {
  @override
  final int typeId = 2;

  @override
  Category read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Category(
      name: fields[0] as String,
      order: fields[1] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, Category obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.order);
  }
}
