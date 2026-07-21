import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Keeps persisted filesystem paths valid when the app container moves.
///
/// iOS stores app data under `/var/mobile/Containers/Data/Application/<UUID>/`
/// and that UUID changes on every install or update — which, for a sideloaded
/// build, means **every 7-day re-sign**. SharedPreferences survives the move,
/// so any absolute path saved under the documents directory quietly goes stale
/// and whatever it pointed at looks like it vanished. Android's
/// `/data/data/<pkg>/` is stable, so none of this is visible there.
///
/// Paths inside the documents directory are persisted with a placeholder token
/// and re-expanded on read. Paths outside it (e.g. a user-picked folder on
/// Android) are stored verbatim, since nothing portable can be said about them.
class PortablePath {
  const PortablePath._();

  static const _docsToken = r'$DOCS$';

  /// True if [value] was written by [store] rather than being a raw path.
  static bool isTokenised(String value) => value.startsWith(_docsToken);

  /// Converts an absolute path into a form that is safe to persist.
  static Future<String> store(String absolute) async {
    final docs = (await getApplicationDocumentsDirectory()).path;
    if (absolute == docs) return _docsToken;
    if (absolute.startsWith('$docs/')) {
      return '$_docsToken${absolute.substring(docs.length)}';
    }
    return absolute;
  }

  /// Expands a persisted value back into an absolute path for the current
  /// container, repairing legacy entries written before tokenisation.
  static Future<String> resolve(String stored) async {
    final docs = (await getApplicationDocumentsDirectory()).path;
    if (stored == _docsToken) return docs;
    if (stored.startsWith(_docsToken)) {
      return '$docs${stored.substring(_docsToken.length)}';
    }

    // Legacy absolute path — either written before this class existed, or by a
    // previous container. If it's gone but the same tail exists under today's
    // documents directory, re-root it so the data comes back.
    if (await _exists(stored)) return stored;
    const marker = '/Documents/';
    final index = stored.indexOf(marker);
    if (index != -1) {
      final candidate = '$docs/${stored.substring(index + marker.length)}';
      if (await _exists(candidate)) return candidate;
    }
    return stored;
  }

  static Future<bool> _exists(String path) async {
    if (path.isEmpty) return false;
    return await Directory(path).exists() || await File(path).exists();
  }
}
