import 'dart:convert';
import 'package:d4rt/d4rt.dart';
import 'package:flutter/foundation.dart';
import '../../model/m_provider.dart';
import '../../model/filter.dart';
import 'document.dart';
import '../../../core/services/webview_service.dart';
import 'http.dart';

class MProviderBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: MProvider,
      name: 'MProvider',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          return MProvider;
        },
      },
      methods: {
        'getPopular': (visitor, target, positionalArgs, namedArgs) =>
            (target as MProvider).getPopular(positionalArgs[0] as int),
        'getLatestUpdates': (visitor, target, positionalArgs, namedArgs) =>
            (target as MProvider).getLatestUpdates(positionalArgs[0] as int),
        'search': (visitor, target, positionalArgs, namedArgs) =>
            (target as MProvider).search(
              positionalArgs[0] as String,
              positionalArgs[1] as int,
              positionalArgs[2] as FilterList,
            ),
        'getDetail': (visitor, target, positionalArgs, namedArgs) =>
            (target as MProvider).getDetail(positionalArgs[0] as String),
        'getPageList': (visitor, target, positionalArgs, namedArgs) =>
            (target as MProvider).getPageList(positionalArgs[0] as String),
        'getFilterList': (visitor, target, positionalArgs, namedArgs) =>
            (target as MProvider).getFilterList(),
        'getSourcePreferences': (visitor, target, positionalArgs, namedArgs) =>
            (target as MProvider).getSourcePreferences(),
      },
      getters: {
        'supportsLatest': (visitor, target) =>
            (target as MProvider).supportsLatest,
        'baseUrl': (visitor, target) => (target as MProvider).baseUrl,
        'headers': (visitor, target) => (target as MProvider).headers,
      },
      setters: {},
    );
  }
}

/// Top-level utility functions available to all extensions.
class MProviderUtilities {
  static void register(D4rt interpreter, String lib) {
    // parseHtml - parse HTML string into a Document
    interpreter.registertopLevelFunction(
      'parseHtml',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        final htmlStr = positionalArgs[0] as String;
        return MDocument(htmlStr);
      },
      sourceUri: lib,
    );

    // substringBefore
    interpreter.registertopLevelFunction(
      'substringBefore',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        final text = positionalArgs[0] as String;
        final delimiter = positionalArgs[1] as String;
        final idx = text.indexOf(delimiter);
        return idx == -1 ? text : text.substring(0, idx);
      },
      sourceUri: lib,
    );

    // substringAfter
    interpreter.registertopLevelFunction(
      'substringAfter',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        final text = positionalArgs[0] as String;
        final delimiter = positionalArgs[1] as String;
        final idx = text.indexOf(delimiter);
        return idx == -1 ? text : text.substring(idx + delimiter.length);
      },
      sourceUri: lib,
    );

    // substringBeforeLast
    interpreter.registertopLevelFunction(
      'substringBeforeLast',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        final text = positionalArgs[0] as String;
        final delimiter = positionalArgs[1] as String;
        final idx = text.lastIndexOf(delimiter);
        return idx == -1 ? text : text.substring(0, idx);
      },
      sourceUri: lib,
    );

    // substringAfterLast
    interpreter.registertopLevelFunction(
      'substringAfterLast',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        final text = positionalArgs[0] as String;
        final delimiter = positionalArgs[1] as String;
        final idx = text.lastIndexOf(delimiter);
        return idx == -1 ? text : text.substring(idx + delimiter.length);
      },
      sourceUri: lib,
    );

    // parseStatus - convert status string to int
    interpreter.registertopLevelFunction(
      'parseStatus',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        final status = (positionalArgs[0] as String).trim().toLowerCase();
        final statusList = positionalArgs.length > 1 ? positionalArgs[1] : null;

        if (statusList is List && statusList.isNotEmpty) {
          for (final entry in statusList) {
            if (entry is Map) {
              for (final key in entry.keys) {
                if (key.toString().toLowerCase() == status) {
                  return entry[key];
                }
              }
            }
          }
        }

        if (status.contains('ongoing') || status.contains('publishing')) return 0;
        if (status.contains('completed') || status.contains('finished')) return 1;
        if (status.contains('hiatus') || status.contains('hold')) return 2;
        if (status.contains('cancel') || status.contains('dropped')) return 3;
        return 5;
      },
      sourceUri: lib,
    );

    // print
    interpreter.registertopLevelFunction(
      'print',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        return null;
      },
      sourceUri: lib,
    );

    // jsonDecode - parse JSON string into native Dart objects (List/Map)
    interpreter.registertopLevelFunction(
      'jsonDecode',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        final jsonStr = positionalArgs[0] as String;
        return json.decode(jsonStr);
      },
      sourceUri: lib,
    );

    // jsonEncode - encode Dart object to JSON string
    interpreter.registertopLevelFunction(
      'jsonEncode',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        return json.encode(positionalArgs[0]);
      },
      sourceUri: lib,
    );

    // listSort - sort a List<Map> by a string key, natively (fast for large lists)
    // Usage: listSort(list, 'favorited', true) → sorted desc by 'favorited'
    interpreter.registertopLevelFunction(
      'listSort',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        final list = (positionalArgs[0] as List).cast<Map>();
        final key = positionalArgs[1] as String;
        final descending = positionalArgs.length > 2 ? positionalArgs[2] as bool : false;
        final sorted = List<Map>.from(list);
        sorted.sort((a, b) {
          final va = a[key];
          final vb = b[key];
          if (va is num && vb is num) {
            return descending ? vb.compareTo(va) : va.compareTo(vb);
          }
          return descending
              ? vb.toString().compareTo(va.toString())
              : va.toString().compareTo(vb.toString());
        });
        return sorted;
      },
      sourceUri: lib,
    );

    // listFilter - filter a List<Map> where map[key] contains value (case-insensitive)
    // Usage: listFilter(list, 'name', 'search term')
    interpreter.registertopLevelFunction(
      'listFilter',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        final list = (positionalArgs[0] as List).cast<Map>();
        final key = positionalArgs[1] as String;
        final value = (positionalArgs[2] as String).toLowerCase();
        return list.where((m) {
          final v = m[key];
          if (v == null) return false;
          return v.toString().toLowerCase().contains(value);
        }).toList();
      },
      sourceUri: lib,
    );

    // listSlice - get a sublist from startIndex to endIndex (clamped)
    // Usage: listSlice(list, 0, 50)
    interpreter.registertopLevelFunction(
      'listSlice',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        final list = positionalArgs[0] as List;
        final start = positionalArgs[1] as int;
        final end = positionalArgs[2] as int;
        final clampedStart = start.clamp(0, list.length);
        final clampedEnd = end.clamp(clampedStart, list.length);
        return list.sublist(clampedStart, clampedEnd);
      },
      sourceUri: lib,
    );

    // captureWebViewRequest - load URL in WebView, capture first request matching pattern
    // Usage: captureWebViewRequest('https://site.com/page', 'ajax/read/chapter')
    // Returns the full captured URL string, or null on timeout
    interpreter.registertopLevelFunction(
      'captureWebViewRequest',
      (visitor, positionalArgs, namedArgs, typeArgs) async {
        if (isBackgroundIsolate) return null;
        final url = positionalArgs[0] as String;
        final pattern = positionalArgs[1] as String;
        final timeout = positionalArgs.length > 2 ? positionalArgs[2] as int : 20;
        return await WebViewService().captureRequest(url, pattern, timeoutSeconds: timeout);
      },
      sourceUri: lib,
    );

    // listExclude - filter out items where map[key] equals any value in excludeList
    // Usage: listExclude(list, 'service', ['discord'])
    interpreter.registertopLevelFunction(
      'listExclude',
      (visitor, positionalArgs, namedArgs, typeArgs) {
        final list = (positionalArgs[0] as List).cast<Map>();
        final key = positionalArgs[1] as String;
        final excludes = (positionalArgs[2] as List).map((e) => e.toString().toLowerCase()).toSet();
        return list.where((m) {
          final v = m[key];
          if (v == null) return true;
          return !excludes.contains(v.toString().toLowerCase());
        }).toList();
      },
      sourceUri: lib,
    );
  }
}
