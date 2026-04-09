import 'package:d4rt/d4rt.dart';
import 'package:flutter/foundation.dart';
import '../../model/m_manga.dart';
import '../../model/m_chapter.dart';

class MMangaBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: MManga,
      name: 'MManga',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          return MManga();
        },
      },
      methods: {},
      getters: {
        'name': (visitor, instance) => (instance as MManga).name,
        'link': (visitor, instance) => (instance as MManga).link,
        'imageUrl': (visitor, instance) => (instance as MManga).imageUrl,
        'description': (visitor, instance) => (instance as MManga).description,
        'author': (visitor, instance) => (instance as MManga).author,
        'artist': (visitor, instance) => (instance as MManga).artist,
        'status': (visitor, instance) => (instance as MManga).status?.index ?? 5,
        'genre': (visitor, instance) => (instance as MManga).genre,
        'chapters': (visitor, instance) => (instance as MManga).chapters,
      },
      setters: {
        'name': (visitor, instance, value) =>
            (instance as MManga).name = value as String?,
        'link': (visitor, instance, value) =>
            (instance as MManga).link = value as String?,
        'imageUrl': (visitor, instance, value) =>
            (instance as MManga).imageUrl = value as String?,
        'description': (visitor, instance, value) =>
            (instance as MManga).description = value as String?,
        'author': (visitor, instance, value) =>
            (instance as MManga).author = value as String?,
        'artist': (visitor, instance, value) =>
            (instance as MManga).artist = value as String?,
        'status': (visitor, instance, value) {
          final idx = value is int ? value : 5;
          (instance as MManga).status = MangaStatus.values[idx.clamp(0, 5)];
        },
        'genre': (visitor, instance, value) {
          if (value is List) {
            (instance as MManga).genre = value.map((e) => e.toString()).toList();
          }
        },
        'chapters': (visitor, instance, value) {
          if (value is List) {
            final chapters = <MChapter>[];
            for (final e in value) {
              if (e is MChapter) {
                chapters.add(e);
              } else if (e is BridgedInstance) {
                chapters.add(e.nativeObject as MChapter);
              } else {
                // Log unknown type for debugging
                debugPrint('[MManga] chapters: unknown item type ${e.runtimeType}');
              }
            }
            (instance as MManga).chapters = chapters;
            debugPrint('[MManga] Set ${chapters.length} chapters');
          } else {
            debugPrint('[MManga] chapters value is ${value.runtimeType}, not List');
          }
        },
      },
    );
  }
}
