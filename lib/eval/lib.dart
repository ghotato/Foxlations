import '../core/models/source_model.dart';
import 'model/m_source.dart';
import 'interface.dart';
import 'dart/service.dart';
import 'javascript/service.dart';

ExtensionService getExtensionService(
    MangaSource source, String sourceCode) {
  final mSource = MSource(
    id: source.id.hashCode,
    name: source.name,
    baseUrl: source.baseUrl,
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
        baseUrl: source.baseUrl,
      );
    case 'dart':
    default:
      return DartExtensionService(
        mSource: mSource,
        sourceCode: sourceCode,
        baseUrl: source.baseUrl,
      );
  }
}

Future<T> withExtensionService<T>(
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
