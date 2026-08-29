import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'package:html/parser.dart' as html_parser;

/// Injects DOM parsing functions into the JS runtime.
class JsDomSelector {
  final JavascriptRuntime _runtime;

  JsDomSelector(this._runtime);

  void init() {
    _runtime.onMessage('ParseHtml', (dynamic args) {
      try {
        final html = args['html'] as String;
        final selector = args['selector'] as String;
        final doc = html_parser.parse(html);
        final elements = doc.querySelectorAll(selector);
        final results = elements.map((e) => {
              'text': e.text.trim(),
              'outerHtml': e.outerHtml,
              'innerHtml': e.innerHtml,
              'attributes': e.attributes,
              'tagName': e.localName,
              'className': e.className,
            }).toList();
        return jsonEncode(results);
      } catch (e) {
        return jsonEncode([]);
      }
    });

    _runtime.onMessage('ParseHtmlFirst', (dynamic args) {
      try {
        final html = args['html'] as String;
        final selector = args['selector'] as String;
        final doc = html_parser.parse(html);
        final el = doc.querySelector(selector);
        if (el == null) return jsonEncode(null);
        return jsonEncode({
          'text': el.text.trim(),
          'outerHtml': el.outerHtml,
          'innerHtml': el.innerHtml,
          'attributes': el.attributes,
          'tagName': el.localName,
          'className': el.className,
        });
      } catch (e) {
        return jsonEncode(null);
      }
    });

    _runtime.evaluate('''
// NOTE: select/selectFirst are SYNCHRONOUS to match the Mangayomi JS contract
// (sources iterate `for (const el of doc.select(...))` without await). QuickJS
// `sendMessage` resolves synchronously, so this works; existing sources that
// `await doc.select(...)` still work (await on a non-Promise is a no-op).
class Document {
  constructor(html) {
    this._html = html;
  }

  select(selector) {
    const result = sendMessage('ParseHtml', JSON.stringify({
      html: this._html,
      selector: selector
    }));
    return JSON.parse(result).map(el => new Element(el, this._html));
  }

  selectFirst(selector) {
    const result = sendMessage('ParseHtmlFirst', JSON.stringify({
      html: this._html,
      selector: selector
    }));
    const data = JSON.parse(result);
    return data ? new Element(data, this._html) : null;
  }

  get body() { return this._html; }
}

class Element {
  constructor(data, parentHtml) {
    this._data = data;
    this._parentHtml = parentHtml || '';
  }

  get text() { return this._data.text || ''; }
  get outerHtml() { return this._data.outerHtml || ''; }
  get innerHtml() { return this._data.innerHtml || ''; }
  get className() { return this._data.className || ''; }
  get tagName() { return this._data.tagName || ''; }

  attr(name) {
    return this._data.attributes ? this._data.attributes[name] : null;
  }

  // getSrc / getHref are GETTERS (property access, no parens) per the Mangayomi
  // contract — sources use `el.getSrc` / `a.getHref`.
  get getSrc() {
    const attrs = this._data.attributes || {};
    return attrs['data-src'] || attrs['data-lazy-src'] || this._extractSrcSet(attrs) || attrs['src'] || '';
  }

  get getHref() {
    const attrs = this._data.attributes || {};
    return attrs['href'] || attrs['data-href'] || '';
  }

  _extractSrcSet(attrs) {
    const srcset = attrs['srcset'];
    if (!srcset) return null;
    return srcset.split(',')[0].trim().split(' ')[0];
  }

  hasAttr(name) {
    return this._data.attributes ? name in this._data.attributes : false;
  }

  select(selector) {
    const result = sendMessage('ParseHtml', JSON.stringify({
      html: this._data.outerHtml || '',
      selector: selector
    }));
    return JSON.parse(result).map(el => new Element(el, this._data.outerHtml));
  }

  selectFirst(selector) {
    const result = sendMessage('ParseHtmlFirst', JSON.stringify({
      html: this._data.outerHtml || '',
      selector: selector
    }));
    const data = JSON.parse(result);
    return data ? new Element(data, this._data.outerHtml) : null;
  }
}
''');
  }

  void dispose() {}
}
