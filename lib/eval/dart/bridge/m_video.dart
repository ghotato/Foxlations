import 'package:d4rt/d4rt.dart';
import '../../model/m_video.dart';

class MTrackBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: MTrack,
      name: 'MTrack',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          return MTrack(
            file: namedArgs.get<String?>('file'),
            label: namedArgs.get<String?>('label'),
          );
        },
      },
      getters: {
        'file': (visitor, target) => (target as MTrack).file,
        'label': (visitor, target) => (target as MTrack).label,
      },
      setters: {
        'file': (visitor, target, value) =>
            (target as MTrack).file = value as String?,
        'label': (visitor, target, value) =>
            (target as MTrack).label = value as String?,
      },
    );
  }
}

class MVideoBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: MVideo,
      name: 'MVideo',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          return MVideo(
            positionalArgs.get<String?>(0) ?? '',
            positionalArgs.get<String?>(1) ?? '',
            positionalArgs.get<String?>(2) ?? '',
            headers: namedArgs.get<Map?>('headers')?.cast<String, String>(),
            subtitles: namedArgs.get<List?>('subtitles')?.cast<MTrack>(),
            audios: namedArgs.get<List?>('audios')?.cast<MTrack>(),
          );
        },
      },
      getters: {
        'url': (visitor, target) => (target as MVideo).url,
        'quality': (visitor, target) => (target as MVideo).quality,
        'originalUrl': (visitor, target) => (target as MVideo).originalUrl,
        'headers': (visitor, target) => (target as MVideo).headers,
        'subtitles': (visitor, target) => (target as MVideo).subtitles,
        'audios': (visitor, target) => (target as MVideo).audios,
      },
      setters: {
        'url': (visitor, target, value) =>
            (target as MVideo).url = value as String,
        'quality': (visitor, target, value) =>
            (target as MVideo).quality = value as String,
        'originalUrl': (visitor, target, value) =>
            (target as MVideo).originalUrl = value as String,
        'headers': (visitor, target, value) =>
            (target as MVideo).headers = (value as Map?)?.cast<String, String>(),
        'subtitles': (visitor, target, value) =>
            (target as MVideo).subtitles = (value as List?)?.cast<MTrack>(),
        'audios': (visitor, target, value) =>
            (target as MVideo).audios = (value as List?)?.cast<MTrack>(),
      },
    );
  }
}
