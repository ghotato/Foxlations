import 'dart:async';
import 'dart:io' show Platform;

import '../core/models/source_model.dart';
import '../core/models/source_settings.dart';
import 'model/m_source.dart';
import 'interface.dart';
import 'dart/service.dart';
import 'javascript/service.dart';

ExtensionService getExtensionService(
    MangaSource source, String sourceCode) {
  // A user-set base URL wins over the one baked into the source — this is how
  // a site that changed domain keeps working without waiting for the extension
  // author to publish an update.
  final override = SourceSettings.cached(source.id).baseUrlOverride;
  final effectiveBaseUrl =
      override.isNotEmpty ? override : source.baseUrl;

  final mSource = MSource(
    id: source.id.hashCode,
    name: source.name,
    baseUrl: effectiveBaseUrl,
    lang: source.lang,
    hasCloudflare: source.hasCloudflare,
    apiUrl: source.apiUrl.isNotEmpty ? source.apiUrl : null,
    dateFormat: source.dateFormat.isNotEmpty ? source.dateFormat : null,
    dateFormatLocale:
        source.dateFormatLocale.isNotEmpty ? source.dateFormatLocale : null,
    additionalParams: source.config.isNotEmpty
        ? source.config.toString()
        : null,
    notes: source.notes.isNotEmpty ? source.notes : null,
  );

  switch (source.sourceCodeLanguage) {
    case 'js':
    case 'javascript':
      return JsExtensionService(
        mSource: mSource,
        sourceCode: sourceCode,
        baseUrl: effectiveBaseUrl,
      );
    case 'dart':
    default:
      return DartExtensionService(
        mSource: mSource,
        sourceCode: sourceCode,
        baseUrl: effectiveBaseUrl,
      );
  }
}

bool _isJsSource(MangaSource source) {
  final lang = source.sourceCodeLanguage;
  return lang == 'js' || lang == 'javascript';
}

/// Serializes JS extension work on iOS — see [withExtensionService].
Future<void> _jsQueue = Future<void>.value();

Future<T> _runExtensionService<T>(
  MangaSource source,
  String sourceCode,
  Future<T> Function(ExtensionService service) action,
) async {
  final service = getExtensionService(source, sourceCode);
  try {
    return await action(service);
  } finally {
    service.dispose();
  }
}

/// Runs [action] against a freshly built extension service, disposing it after.
///
/// On iOS, JS sources are queued so only ONE JavaScriptCore runtime is alive at
/// a time. flutter_js runs QuickJS on Android but JavaScriptCore on iOS, and
/// the JSC binding keeps its Dart `sendMessage` callback in a **static** field
/// (`jscore_runtime.dart:171`) because an FFI callback must be top-level.
/// Constructing a second runtime therefore overwrites the bridge for every
/// runtime already live: preference lookups resolve against the wrong source,
/// and promises get built on the wrong JSGlobalContext so they never settle.
/// `dispose()` only releases the context and never clears the static, so a
/// disposed runtime can leave the survivors calling into freed memory.
///
/// Global search and migrate fan out across every installed source at once,
/// which is exactly the pattern that triggers it. QuickJS installs the callback
/// per-instance, so Android needs no such guard and keeps running in parallel.
Future<T> withExtensionService<T>(
  MangaSource source,
  String sourceCode,
  Future<T> Function(ExtensionService service) action,
) async {
  if (!Platform.isIOS || !_isJsSource(source)) {
    return _runExtensionService(source, sourceCode, action);
  }

  final previous = _jsQueue;
  final gate = Completer<void>();
  _jsQueue = gate.future;
  await previous;
  try {
    return await _runExtensionService(source, sourceCode, action);
  } finally {
    // Always completes normally so one failing source can't stall the queue.
    gate.complete();
  }
}
