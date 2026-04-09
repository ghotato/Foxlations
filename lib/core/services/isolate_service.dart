import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rhttp/rhttp.dart' as rhttp;
import '../models/source_model.dart';
import '../models/installed_source_model.dart';
import '../../eval/lib.dart';
import '../../eval/dart/bridge/http.dart' show isBackgroundIsolate;

/// Persistent background isolate for running extension service calls
/// off the main thread, preventing OOM crashes in the reader.
class IsolateService {
  bool _isRunning = false;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  StreamSubscription? _receiveSub;
  SendPort? _sendPort;

  /// Callback for Cloudflare resolution on the main thread.
  /// Set by the app to handle WebView-based CF bypass.
  Future<Map<String, String>?> Function(String url)? onCloudflareNeeded;

  Future<void> start() async {
    if (_isRunning) return;
    try {
      await _init();
    } catch (e) {
      debugPrint('[IsolateService] Failed to start: $e');
      await stop();
    }
  }

  Future<void> _init() async {
    _receivePort = ReceivePort();
    final rootToken = RootIsolateToken.instance!;

    _isolate = await Isolate.spawn(
      _entryPoint,
      _IsolateInit(
        sendPort: _receivePort!.sendPort,
        rootToken: rootToken,
      ),
    );

    final completer = Completer<SendPort>();
    _receiveSub = _receivePort!.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      } else if (message is Map && message['type'] == 'log') {
        debugPrint('[Isolate] ${message['message']}');
      }
    });

    _sendPort = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw StateError('Isolate handshake timed out'),
    );
    _isRunning = true;
    debugPrint('[IsolateService] Started');
  }

  /// Entry point for the background isolate.
  static Future<void> _entryPoint(_IsolateInit init) async {
    BackgroundIsolateBinaryMessenger.ensureInitialized(init.rootToken);
    try {
      await rhttp.Rhttp.init();
    } catch (_) {
      // May already be initialized — not fatal
    }
    isBackgroundIsolate = true;

    final receivePort = ReceivePort();
    init.sendPort.send(receivePort.sendPort);

    receivePort.listen((message) async {
      if (message is Map<String, dynamic>) {
        final responsePort = message['responsePort'] as SendPort;
        try {
          final sourceJson = message['sourceJson'] as Map<String, dynamic>;
          final sourceCode = message['sourceCode'] as String;
          final repoUrl = message['repoUrl'] as String? ?? '';
          final serviceType = message['serviceType'] as String;
          final url = message['url'] as String?;
          final page = message['page'] as int?;
          final query = message['query'] as String?;

          final source = MangaSource.fromJson(sourceJson, repoUrl);

          final result = await withExtensionService(
            source,
            sourceCode,
            (service) async {
              switch (serviceType) {
                case 'getPopular':
                  return await service.getPopular(page!);
                case 'getLatestUpdates':
                  return await service.getLatestUpdates(page!);
                case 'search':
                  return await service.search(query!, page!, []);
                case 'getDetail':
                  return await service.getDetail(url!);
                case 'getPageList':
                  return await service.getPageList(url!);
                default:
                  throw Exception('Unknown service: $serviceType');
              }
            },
          );
          responsePort.send({'success': true, 'data': result});
        } catch (e) {
          responsePort.send({'success': false, 'error': e.toString()});
        }
      } else if (message == 'dispose') {
        receivePort.close();
      }
    });
  }

  /// Call an extension service method in the background isolate.
  /// Starts the isolate lazily if not already running.
  Future<T> call<T>({
    required InstalledSource installedSource,
    required String serviceType,
    String? url,
    int? page,
    String? query,
  }) async {
    if (!_isRunning) {
      await start();
    }
    if (_sendPort == null) {
      throw Exception('IsolateService failed to start');
    }

    final responsePort = ReceivePort();
    final completer = Completer<T>();
    late final StreamSubscription sub;

    final timer = Timer(const Duration(seconds: 40), () {
      if (!completer.isCompleted) {
        sub.cancel();
        responsePort.close();
        completer.completeError(
            TimeoutException('Isolate response timeout (40s)'));
      }
    });

    sub = responsePort.listen((response) {
      timer.cancel();
      sub.cancel();
      responsePort.close();
      if (response is Map<String, dynamic>) {
        if (response['success'] == true) {
          completer.complete(response['data'] as T);
        } else {
          completer.completeError(Exception(response['error']));
        }
      } else {
        completer.completeError(Exception('Invalid isolate response'));
      }
    });

    _sendPort!.send({
      'sourceJson': installedSource.source.toJson(),
      'sourceCode': installedSource.sourceCode,
      'repoUrl': installedSource.source.repoUrl,
      'serviceType': serviceType,
      'url': url,
      'page': page,
      'query': query,
      'responsePort': responsePort.sendPort,
    });

    return completer.future;
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    _sendPort?.send('dispose');
    _isolate?.kill(priority: Isolate.immediate);
    await _receiveSub?.cancel();
    _receivePort?.close();
    _receiveSub = null;
    _sendPort = null;
    _isolate = null;
    _receivePort = null;
    _isRunning = false;
  }
}

class _IsolateInit {
  final SendPort sendPort;
  final RootIsolateToken rootToken;
  _IsolateInit({required this.sendPort, required this.rootToken});
}

/// Global isolate service instance.
final isolateService = IsolateService();
