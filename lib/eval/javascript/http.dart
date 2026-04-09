import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import '../../core/services/cookie_store.dart';

/// Injects HTTP client functions into the JS runtime.
class JsHttpClient {
  final JavascriptRuntime _runtime;

  JsHttpClient(this._runtime);

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'User-Agent': CookieStore.defaultUserAgent,
    },
  ));

  void init() {
    // Register the HTTP bridge channel
    _runtime.onMessage('HttpGet', (dynamic args) async {
      try {
        final url = args['url'] as String;
        final headers = (args['headers'] as Map?)?.cast<String, String>() ?? {};
        final response = await _dio.get<String>(
          url,
          options: Options(
            headers: headers,
            responseType: ResponseType.plain,
          ),
        );
        return jsonEncode({
          'statusCode': response.statusCode,
          'body': response.data ?? '',
          'headers': response.headers.map
              .map((k, v) => MapEntry(k, v.join(', '))),
        });
      } catch (e) {
        return jsonEncode({'statusCode': 0, 'body': '', 'error': e.toString()});
      }
    });

    _runtime.onMessage('HttpPost', (dynamic args) async {
      try {
        final url = args['url'] as String;
        final headers = (args['headers'] as Map?)?.cast<String, String>() ?? {};
        final body = args['body'];
        final response = await _dio.post<String>(
          url,
          data: body,
          options: Options(
            headers: headers,
            responseType: ResponseType.plain,
          ),
        );
        return jsonEncode({
          'statusCode': response.statusCode,
          'body': response.data ?? '',
          'headers': response.headers.map
              .map((k, v) => MapEntry(k, v.join(', '))),
        });
      } catch (e) {
        return jsonEncode({'statusCode': 0, 'body': '', 'error': e.toString()});
      }
    });

    // Inject JS Client class
    _runtime.evaluate('''
class Client {
  constructor() {}

  async get(url, headers) {
    const result = await sendMessage('HttpGet', JSON.stringify({
      url: url,
      headers: headers || {}
    }));
    return JSON.parse(result);
  }

  async post(url, headers, body) {
    const result = await sendMessage('HttpPost', JSON.stringify({
      url: url,
      headers: headers || {},
      body: body || ''
    }));
    return JSON.parse(result);
  }
}
''');
  }
}
