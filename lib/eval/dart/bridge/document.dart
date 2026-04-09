import 'package:d4rt/d4rt.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

/// Bridges HTML document parsing for Dart extensions.
class DocumentBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: MDocument,
      name: 'Document',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          final html = positionalArgs[0] as String;
          return MDocument(html);
        },
      },
      methods: {
        'select': (visitor, instance, positionalArgs, namedArgs) {
          return (instance as MDocument).select(positionalArgs[0] as String);
        },
        'selectFirst': (visitor, instance, positionalArgs, namedArgs) {
          return (instance as MDocument)
              .selectFirst(positionalArgs[0] as String);
        },
      },
      getters: {
        'body': (visitor, instance) => (instance as MDocument).body,
      },
      setters: {},
    );
  }
}

class MDocument {
  final dom.Document _document;

  MDocument(String html) : _document = html_parser.parse(html);

  List<MElement> select(String selector) {
    try {
      return _document
          .querySelectorAll(selector)
          .map((e) => MElement(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  MElement? selectFirst(String selector) {
    try {
      final el = _document.querySelector(selector);
      return el != null ? MElement(el) : null;
    } catch (_) {
      return null;
    }
  }

  String get body => _document.body?.innerHtml ?? '';
}

class MElement {
  final dom.Element _element;

  MElement(this._element);

  String get text => _element.text.trim();
  String get outerHtml => _element.outerHtml;
  String get innerHtml => _element.innerHtml;

  String? attr(String name) => _element.attributes[name];

  String? getSrc() {
    return _element.attributes['data-src'] ??
        _element.attributes['data-lazy-src'] ??
        _extractSrcSet() ??
        _element.attributes['src'];
  }

  String? _extractSrcSet() {
    final srcset = _element.attributes['srcset'];
    if (srcset == null || srcset.isEmpty) return null;
    return srcset.split(',').first.trim().split(' ').first;
  }

  List<MElement> select(String selector) {
    try {
      return _element
          .querySelectorAll(selector)
          .map((e) => MElement(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  MElement? selectFirst(String selector) {
    try {
      final el = _element.querySelector(selector);
      return el != null ? MElement(el) : null;
    } catch (_) {
      return null;
    }
  }

  bool hasAttr(String name) => _element.attributes.containsKey(name);

  String get className => _element.className;
  String get id => _element.id;
  String get tagName => _element.localName ?? '';
}

class ElementBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: MElement,
      name: 'Element',
      constructors: {},
      methods: {
        'attr': (visitor, instance, positionalArgs, namedArgs) {
          return (instance as MElement).attr(positionalArgs[0] as String);
        },
        'getSrc': (visitor, instance, positionalArgs, namedArgs) {
          return (instance as MElement).getSrc();
        },
        'select': (visitor, instance, positionalArgs, namedArgs) {
          return (instance as MElement).select(positionalArgs[0] as String);
        },
        'selectFirst': (visitor, instance, positionalArgs, namedArgs) {
          return (instance as MElement)
              .selectFirst(positionalArgs[0] as String);
        },
        'hasAttr': (visitor, instance, positionalArgs, namedArgs) {
          return (instance as MElement).hasAttr(positionalArgs[0] as String);
        },
      },
      getters: {
        'text': (visitor, instance) => (instance as MElement).text,
        'outerHtml': (visitor, instance) => (instance as MElement).outerHtml,
        'innerHtml': (visitor, instance) => (instance as MElement).innerHtml,
        'className': (visitor, instance) => (instance as MElement).className,
        'id': (visitor, instance) => (instance as MElement).id,
        'tagName': (visitor, instance) => (instance as MElement).tagName,
      },
      setters: {},
    );
  }
}
