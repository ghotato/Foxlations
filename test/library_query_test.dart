import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/core/models/library_settings.dart';
import 'package:manga_reader/core/models/manga_model.dart';
import 'package:manga_reader/core/utils/library_query.dart';

LibraryManga m(
  String title, {
  String source = 's1',
  int total = 10,
  int read = 10,
  String status = 'ongoing',
  DateTime? added,
  DateTime? lastRead,
}) =>
    LibraryManga(
      sourceId: source,
      url: '/$title',
      title: title,
      coverUrl: '',
      status: status,
      addedAt: added ?? DateTime(2024, 1, 1),
      lastReadAt: lastRead,
      totalChapters: total,
      readChapters: read,
    );

void main() {
  group('filters', () {
    final lib = [
      m('Alpha', total: 10, read: 4),                    // 6 unread
      m('Beta', total: 5, read: 5, status: 'completed'), // 0 unread
      m('Gamma', source: 's2', total: 3, read: 3),
    ];

    test('no filters returns everything', () {
      expect(applyLibraryQuery(lib, const LibrarySettings()).length, 3);
    });

    test('unread keeps only entries with unread chapters', () {
      final r = applyLibraryQuery(
          lib, const LibrarySettings(filterUnread: true));
      expect(r.map((e) => e.title), ['Alpha']);
    });

    test('completed keeps only completed entries', () {
      final r = applyLibraryQuery(
          lib, const LibrarySettings(filterCompleted: true));
      expect(r.map((e) => e.title), ['Beta']);
    });

    test('downloaded uses the caller-supplied key set', () {
      final r = applyLibraryQuery(
        lib,
        const LibrarySettings(filterDownloaded: true),
        downloadedKeys: {'s2::/Gamma'},
      );
      expect(r.map((e) => e.title), ['Gamma']);
    });

    test('source filter narrows to the chosen sources', () {
      final r = applyLibraryQuery(
          lib, const LibrarySettings(filterSourceIds: {'s2'}));
      expect(r.map((e) => e.title), ['Gamma']);
    });

    test('filters combine (AND, not OR)', () {
      final r = applyLibraryQuery(
        lib,
        const LibrarySettings(filterUnread: true, filterCompleted: true),
      );
      expect(r, isEmpty); // Alpha is unread but not completed
    });
  });

  group('sorting', () {
    test('alphabetical is case-insensitive and reversible', () {
      final lib = [m('banana'), m('Apple'), m('cherry')];
      expect(
        applyLibraryQuery(lib, const LibrarySettings()).map((e) => e.title),
        ['Apple', 'banana', 'cherry'],
      );
      expect(
        applyLibraryQuery(lib, const LibrarySettings(sortAscending: false))
            .map((e) => e.title),
        ['cherry', 'banana', 'Apple'],
      );
    });

    test('unread sorts by remaining chapters', () {
      final lib = [
        m('few', total: 10, read: 9),   // 1
        m('many', total: 10, read: 0),  // 10
        m('none', total: 10, read: 10), // 0
      ];
      expect(
        applyLibraryQuery(lib, const LibrarySettings(sort: LibrarySort.unread))
            .map((e) => e.title),
        ['none', 'few', 'many'],
      );
    });

    test('never-read entries sort before read ones by Last Read', () {
      final lib = [
        m('read', lastRead: DateTime(2025, 5, 1)),
        m('unreadEver'),
      ];
      expect(
        applyLibraryQuery(
                lib, const LibrarySettings(sort: LibrarySort.lastRead))
            .map((e) => e.title),
        ['unreadEver', 'read'],
      );
    });

    test('date added orders oldest first when ascending', () {
      final lib = [
        m('new', added: DateTime(2026, 1, 1)),
        m('old', added: DateTime(2020, 1, 1)),
      ];
      expect(
        applyLibraryQuery(
                lib, const LibrarySettings(sort: LibrarySort.dateAdded))
            .map((e) => e.title),
        ['old', 'new'],
      );
    });

    test('chapter fetch date puts never-fetched entries first', () {
      final lib = [
        m('fetchedRecently')..lastChapterFetchAt = DateTime(2026, 7, 1),
        m('neverFetched'),
        m('fetchedLongAgo')..lastChapterFetchAt = DateTime(2025, 1, 1),
      ];
      expect(
        applyLibraryQuery(lib,
                const LibrarySettings(sort: LibrarySort.chapterFetchDate))
            .map((e) => e.title),
        ['neverFetched', 'fetchedLongAgo', 'fetchedRecently'],
      );
    });

    test('ties break on title so order is stable across rebuilds', () {
      final lib = [m('Zeta', total: 5, read: 5), m('Alpha', total: 5, read: 5)];
      final once =
          applyLibraryQuery(lib, const LibrarySettings(sort: LibrarySort.unread));
      final twice =
          applyLibraryQuery(lib, const LibrarySettings(sort: LibrarySort.unread));
      expect(once.map((e) => e.title), ['Alpha', 'Zeta']);
      expect(twice.map((e) => e.title), once.map((e) => e.title));
    });

    test('does not reorder the caller\'s list in place', () {
      final lib = [m('Zeta'), m('Alpha')];
      applyLibraryQuery(lib, const LibrarySettings());
      expect(lib.map((e) => e.title), ['Zeta', 'Alpha']);
    });
  });
}
