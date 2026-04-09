import 'package:flutter_js/flutter_js.dart';

/// Injects utility functions into the JS runtime.
class JsUtils {
  final JavascriptRuntime _runtime;

  JsUtils(this._runtime);

  void init() {
    _runtime.evaluate('''
async function jsonStringify(fn) {
    return JSON.stringify(await fn());
}

function slugify(text) {
    return text.toString().toLowerCase()
        .replace(/\\s+/g, '-')
        .replace(/[^\\w\\-]+/g, '')
        .replace(/\\-\\-+/g, '-')
        .replace(/^-+/, '')
        .replace(/-+\$/, '');
}
''');
  }
}
