import 'package:d4rt/d4rt.dart';
import '../../model/source_preference.dart';

class SourcePreferenceBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: SourcePreference,
      name: 'SourcePreference',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          return SourcePreference(
            key: namedArgs['key'] as String? ?? '',
            title: namedArgs['title'] as String? ?? '',
            summary: namedArgs['summary'] as String?,
            defaultValue: namedArgs['defaultValue'],
            type: namedArgs['type'] as String? ?? 'switch',
            entries: (namedArgs['entries'] as List?)?.cast<SourcePreferenceEntry>(),
          );
        },
      },
      methods: {},
      getters: {
        'key': (visitor, instance) => (instance as SourcePreference).key,
        'title': (visitor, instance) => (instance as SourcePreference).title,
        'summary': (visitor, instance) => (instance as SourcePreference).summary,
        'defaultValue': (visitor, instance) =>
            (instance as SourcePreference).defaultValue,
        'type': (visitor, instance) => (instance as SourcePreference).type,
        'entries': (visitor, instance) => (instance as SourcePreference).entries,
      },
      setters: {},
    );
  }
}

class SourcePreferenceEntryBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: SourcePreferenceEntry,
      name: 'SourcePreferenceEntry',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          return SourcePreferenceEntry(
            title: namedArgs['title'] as String? ?? '',
            value: namedArgs['value'],
          );
        },
      },
      methods: {},
      getters: {
        'title': (visitor, instance) =>
            (instance as SourcePreferenceEntry).title,
        'value': (visitor, instance) =>
            (instance as SourcePreferenceEntry).value,
      },
      setters: {},
    );
  }
}
