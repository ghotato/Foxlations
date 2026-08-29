import 'package:d4rt/d4rt.dart';
import '../../model/source_preference.dart';
import '../../model/preferences.dart';

List<String>? _stringList(Object? v) =>
    (v as List?)?.map((e) => '$e').toList();

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

/// Bridges the m2k3a-style preference constructors sources call inside
/// `getSourcePreferences()`. Each produces its own native model object (which
/// knows how to collapse into a [SourcePreference]); the service reads their
/// declared defaults to seed the preference cache. Constructors read only the
/// named args they know and ignore any extras, so minor source variations
/// don't break registration.
class EditTextPreferenceBridge {
  static BridgedClass get bridgedClass => BridgedClass(
        nativeType: EditTextPreference,
        name: 'EditTextPreference',
        constructors: {
          '': (visitor, positionalArgs, namedArgs) => EditTextPreference(
                key: namedArgs['key'] as String?,
                title: namedArgs['title'] as String?,
                summary: namedArgs['summary'] as String?,
                value: namedArgs['value'] as String?,
                text: namedArgs['text'] as String?,
                dialogTitle: namedArgs['dialogTitle'] as String?,
                dialogMessage: namedArgs['dialogMessage'] as String?,
              ),
        },
        methods: {},
        getters: {
          'key': (visitor, i) => (i as EditTextPreference).key,
        },
        setters: {},
      );
}

class ListPreferenceBridge {
  static BridgedClass get bridgedClass => BridgedClass(
        nativeType: ListPreference,
        name: 'ListPreference',
        constructors: {
          '': (visitor, positionalArgs, namedArgs) => ListPreference(
                key: namedArgs['key'] as String?,
                title: namedArgs['title'] as String?,
                summary: namedArgs['summary'] as String?,
                valueIndex: namedArgs['valueIndex'] as int?,
                entries: _stringList(namedArgs['entries']),
                entryValues: _stringList(namedArgs['entryValues']),
              ),
        },
        methods: {},
        getters: {
          'key': (visitor, i) => (i as ListPreference).key,
        },
        setters: {},
      );
}

class MultiSelectListPreferenceBridge {
  static BridgedClass get bridgedClass => BridgedClass(
        nativeType: MultiSelectListPreference,
        name: 'MultiSelectListPreference',
        constructors: {
          '': (visitor, positionalArgs, namedArgs) =>
              MultiSelectListPreference(
                key: namedArgs['key'] as String?,
                title: namedArgs['title'] as String?,
                summary: namedArgs['summary'] as String?,
                entries: _stringList(namedArgs['entries']),
                entryValues: _stringList(namedArgs['entryValues']),
                values: _stringList(namedArgs['values']),
              ),
        },
        methods: {},
        getters: {
          'key': (visitor, i) => (i as MultiSelectListPreference).key,
        },
        setters: {},
      );
}

class CheckBoxPreferenceBridge {
  static BridgedClass get bridgedClass => BridgedClass(
        nativeType: CheckBoxPreference,
        name: 'CheckBoxPreference',
        constructors: {
          '': (visitor, positionalArgs, namedArgs) => CheckBoxPreference(
                key: namedArgs['key'] as String?,
                title: namedArgs['title'] as String?,
                summary: namedArgs['summary'] as String?,
                value: namedArgs['value'] as bool?,
              ),
        },
        methods: {},
        getters: {
          'key': (visitor, i) => (i as CheckBoxPreference).key,
        },
        setters: {},
      );
}

class SwitchPreferenceCompatBridge {
  static BridgedClass get bridgedClass => BridgedClass(
        nativeType: SwitchPreferenceCompat,
        name: 'SwitchPreferenceCompat',
        constructors: {
          '': (visitor, positionalArgs, namedArgs) => SwitchPreferenceCompat(
                key: namedArgs['key'] as String?,
                title: namedArgs['title'] as String?,
                summary: namedArgs['summary'] as String?,
                value: namedArgs['value'] as bool?,
              ),
        },
        methods: {},
        getters: {
          'key': (visitor, i) => (i as SwitchPreferenceCompat).key,
        },
        setters: {},
      );
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
