import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/core/services/backup_service.dart';

/// A stand-in "protobuf payload" — content doesn't matter, only that unwrapping
/// returns exactly these bytes.
final payload = Uint8List.fromList(utf8.encode('PROTO-PAYLOAD-${'x' * 200}'));

Uint8List gzipped(List<int> data) =>
    Uint8List.fromList(GZipEncoder().encode(data));

Uint8List zipped(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  // store (no deflate) keeps the test independent of compression details
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  group('unwrapBackupBytes', () {
    test('gzip (.tachibk / .proto.gz) unwraps to the payload', () {
      expect(unwrapBackupBytes(gzipped(payload)), equals(payload));
    });

    test('raw protobuf passes through untouched', () {
      expect(unwrapBackupBytes(payload), equals(payload));
    });

    test('zip (.tmb) containing a gzipped backup unwraps fully', () {
      final tmb = zipped({'backup.proto.gz': gzipped(payload)});
      expect(unwrapBackupBytes(tmb), equals(payload));
    });

    test('zip containing a plain (ungzipped) backup unwraps', () {
      final tmb = zipped({'library.proto': payload});
      expect(unwrapBackupBytes(tmb), equals(payload));
    });

    test('prefers the backup-looking entry over a larger unrelated file', () {
      final tmb = zipped({
        'covers/big-cover.jpg': List<int>.filled(5000, 7),
        'backup.proto.gz': gzipped(payload),
      });
      expect(unwrapBackupBytes(tmb), equals(payload));
    });

    test('with no backup-looking name, falls back to the largest entry', () {
      final tmb = zipped({
        'tiny.bin': List<int>.filled(10, 1),
        'library.bin': payload,
      });
      expect(unwrapBackupBytes(tmb), equals(payload));
    });

    test('empty archive fails with a clear message, not a RangeError', () {
      expect(
        () => unwrapBackupBytes(zipped({})),
        throwsA(isA<FormatException>()),
      );
    });

    test('deeply nested archives are rejected rather than looping', () {
      final inner = zipped({'a.bin': payload});
      final outer = zipped({'b.bin': inner});
      final outerer = zipped({'c.bin': outer});
      expect(() => unwrapBackupBytes(outerer), throwsA(isA<FormatException>()));
    });

    test('a .tmb renamed to .tachibk still works (name is never trusted)', () {
      // Same bytes either way — detection is by magic number, not extension.
      final tmb = zipped({'backup.proto.gz': gzipped(payload)});
      expect(unwrapBackupBytes(tmb), equals(payload));
    });
  });
}
