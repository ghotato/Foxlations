import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/m_source.dart';

/// Injects SharedPreferences access into the JS runtime.
class JsPreferences {
  final JavascriptRuntime _runtime;
  final MSource _source;

  JsPreferences(this._runtime, this._source);

  void init() {
    final prefKeyPrefix = 'source_pref_${_source.id}_';

    _runtime.onMessage('GetPref', (dynamic args) async {
      final prefs = await SharedPreferences.getInstance();
      final key = '$prefKeyPrefix${args['key']}';
      final value = prefs.get(key);
      return jsonEncode({'value': value});
    });

    _runtime.onMessage('SetPref', (dynamic args) async {
      final prefs = await SharedPreferences.getInstance();
      final key = '$prefKeyPrefix${args['key']}';
      final value = args['value'];
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      }
      return jsonEncode({'success': true});
    });

    _runtime.evaluate('''
class SharedPreferences {
  async get(key) {
    const result = await sendMessage('GetPref', JSON.stringify({ key: key }));
    return JSON.parse(result).value;
  }

  async set(key, value) {
    await sendMessage('SetPref', JSON.stringify({ key: key, value: value }));
  }
}
''');
  }
}
