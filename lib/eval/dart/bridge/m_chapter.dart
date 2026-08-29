import 'package:d4rt/d4rt.dart';
import '../../model/m_chapter.dart';

class MChapterBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: MChapter,
      name: 'MChapter',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          return MChapter();
        },
      },
      methods: {},
      getters: {
        'name': (visitor, instance) => (instance as MChapter).name,
        'url': (visitor, instance) => (instance as MChapter).url,
        'dateUpload': (visitor, instance) => (instance as MChapter).dateUpload,
        'scanlator': (visitor, instance) => (instance as MChapter).scanlator,
      },
      setters: {
        'name': (visitor, instance, value) =>
            (instance as MChapter).name = value as String?,
        'url': (visitor, instance, value) =>
            (instance as MChapter).url = value as String?,
        'dateUpload': (visitor, instance, value) =>
            (instance as MChapter).dateUpload = value?.toString(),
        'scanlator': (visitor, instance, value) =>
            (instance as MChapter).scanlator = value as String?,
      },
    );
  }
}
