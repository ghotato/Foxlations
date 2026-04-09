import 'package:d4rt/d4rt.dart';
import '../../model/m_source.dart';

class MSourceBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: MSource,
      name: 'MSource',
      constructors: {},
      methods: {},
      getters: {
        'id': (visitor, instance) => (instance as MSource).id,
        'name': (visitor, instance) => (instance as MSource).name,
        'baseUrl': (visitor, instance) => (instance as MSource).baseUrl,
        'lang': (visitor, instance) => (instance as MSource).lang,
        'hasCloudflare': (visitor, instance) =>
            (instance as MSource).hasCloudflare,
        'apiUrl': (visitor, instance) => (instance as MSource).apiUrl,
        'dateFormat': (visitor, instance) => (instance as MSource).dateFormat,
        'dateFormatLocale': (visitor, instance) =>
            (instance as MSource).dateFormatLocale,
        'additionalParams': (visitor, instance) =>
            (instance as MSource).additionalParams,
        'notes': (visitor, instance) => (instance as MSource).notes,
      },
      setters: {},
    );
  }
}
