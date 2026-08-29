import 'source_preference.dart';

/// The preference types Mangayomi/m2k3a sources construct inside their
/// `getSourcePreferences()`. Each carries its own `key` (m2k3a style) and knows
/// how to collapse into a Foxlations [SourcePreference] whose `defaultValue`
/// seeds the pref cache — so a source's declared defaults (base-URL overrides,
/// preferred quality/server, the enabled-hosts multi-select) take effect
/// without the user opening settings.
List<SourcePreferenceEntry>? _entries(
    List<String>? entries, List<String>? entryValues) {
  if (entryValues == null) return null;
  final out = <SourcePreferenceEntry>[];
  for (var i = 0; i < entryValues.length; i++) {
    out.add(SourcePreferenceEntry(
      title: (entries != null && i < entries.length)
          ? entries[i]
          : entryValues[i],
      value: entryValues[i],
    ));
  }
  return out;
}

class EditTextPreference {
  final String? key, title, summary, value, text, dialogTitle, dialogMessage;
  EditTextPreference({
    this.key,
    this.title,
    this.summary,
    this.value,
    this.text,
    this.dialogTitle,
    this.dialogMessage,
  });

  SourcePreference toPref() => SourcePreference(
        key: key ?? '',
        title: title ?? '',
        summary: summary,
        type: 'edit_text',
        defaultValue: value ?? text,
      );
}

class ListPreference {
  final String? key, title, summary;
  final int? valueIndex;
  final List<String>? entries, entryValues;
  ListPreference({
    this.key,
    this.title,
    this.summary,
    this.valueIndex,
    this.entries,
    this.entryValues,
  });

  SourcePreference toPref() {
    dynamic def;
    final ev = entryValues;
    final i = valueIndex ?? 0;
    if (ev != null && i >= 0 && i < ev.length) def = ev[i];
    return SourcePreference(
      key: key ?? '',
      title: title ?? '',
      summary: summary,
      type: 'list',
      defaultValue: def,
      entries: _entries(entries, entryValues),
    );
  }
}

class MultiSelectListPreference {
  final String? key, title, summary;
  final List<String>? entries, entryValues, values;
  MultiSelectListPreference({
    this.key,
    this.title,
    this.summary,
    this.entries,
    this.entryValues,
    this.values,
  });

  SourcePreference toPref() => SourcePreference(
        key: key ?? '',
        title: title ?? '',
        summary: summary,
        type: 'multi_select',
        // The enabled set is a list; keep it a list so a source's
        // `hosterSelection.contains(name)` sees every default host.
        defaultValue: values ?? entryValues ?? const <String>[],
        entries: _entries(entries, entryValues),
      );
}

class CheckBoxPreference {
  final String? key, title, summary;
  final bool? value;
  CheckBoxPreference({this.key, this.title, this.summary, this.value});

  SourcePreference toPref() => SourcePreference(
        key: key ?? '',
        title: title ?? '',
        summary: summary,
        type: 'switch',
        defaultValue: value ?? false,
      );
}

class SwitchPreferenceCompat {
  final String? key, title, summary;
  final bool? value;
  SwitchPreferenceCompat({this.key, this.title, this.summary, this.value});

  SourcePreference toPref() => SourcePreference(
        key: key ?? '',
        title: title ?? '',
        summary: summary,
        type: 'switch',
        defaultValue: value ?? false,
      );
}
