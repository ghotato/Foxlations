import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_logger.dart';

/// Surfaces crashes that happen OUTSIDE Dart — chiefly the embedded JVM aborting
/// natively — into the in-app error log, so they don't require digging through the
/// OS crash reports. The JVM writes `hs_err_<pid>.log` (its fatal-error report) and
/// mirrors stderr to `jvm_stderr.txt` in the app documents dir; a native abort kills
/// the process before Dart can log anything, so we detect and report on the NEXT
/// launch, then mark the artifacts read so each crash is logged once.
class CrashReporter {
  static Future<void> reportPreviousCrash() async {
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      if (!await dir.exists()) return;

      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : entity.path.split(Platform.pathSeparator).last;
        // The JVM's fatal-error report (written on any VM abort/crash).
        if (name.startsWith('hs_err_') && name.endsWith('.log')) {
          await _report(entity, 'Extension engine crashed (native)');
        }
      }

      // stderr capture — holds the fatal report even when hs_err wasn't produced.
      final stderr = File('${dir.path}${Platform.pathSeparator}jvm_stderr.txt');
      if (await stderr.exists()) {
        final text = await stderr.readAsString();
        const markers = [
          'fatal error', 'SIGSEGV', 'SIGBUS', 'SIGABRT', 'SIGILL',
          'Internal Error', 'ShouldNotReachHere', 'guarantee(',
        ];
        if (markers.any(text.contains)) {
          await _report(stderr, 'Extension engine error output');
        }
      }
    } catch (_) {
      // Best-effort; never let crash reporting crash startup.
    }
  }

  static Future<void> _report(File file, String title) async {
    try {
      final lines = await file.readAsLines();
      if (lines.isEmpty) {
        await file.rename('${file.path}.logged');
        return;
      }
      // The header (signal + problematic frame) is the useful part; cap the size.
      final head = lines.take(40).join('\n');
      await logger.error(title, category: LogCategory.extension, detail: head);
      // Mark read so the same crash isn't re-logged on every subsequent launch.
      await file.rename('${file.path}.logged');
    } catch (_) {}
  }
}
