import 'package:d4rt/d4rt.dart';
import 'http.dart';
import 'document.dart';
import 'm_manga.dart';
import 'm_pages.dart';
import 'm_chapter.dart';
import 'm_source.dart';
import 'm_status.dart';
import 'm_provider.dart';
import 'm_video.dart';
import 'filter.dart';
import 'source_preference.dart';
import 'webview.dart';

class RegistrerBridge {
  static void registerBridge(D4rt interpreter) {
    const libs = [
      'package:manga_reader/eval',
      'package:foxlations/bridge_lib.dart',
      'package:mangayomi/bridge_lib.dart',
    ];

    for (final lib in libs) {
      // HTTP
      interpreter.registerBridgedClass(HttpBridge.bridgedClass, lib);
      interpreter.registerBridgedClass(HttpResponseBridge.bridgedClass, lib);

      // WebView (captureRequest, fetchHtml for dynamic video extraction)
      interpreter.registerBridgedClass(WebViewBridge.bridgedClass, lib);

      // DOM
      interpreter.registerBridgedClass(DocumentBridge.bridgedClass, lib);
      interpreter.registerBridgedClass(ElementBridge.bridgedClass, lib);

      // Models
      interpreter.registerBridgedClass(MMangaBridge.bridgedClass, lib);
      interpreter.registerBridgedClass(MPagesBridge.bridgedClass, lib);
      interpreter.registerBridgedClass(MChapterBridge.bridgedClass, lib);
      interpreter.registerBridgedClass(MSourceBridge.bridgedClass, lib);
      interpreter.registerBridgedClass(MVideoBridge.bridgedClass, lib);
      interpreter.registerBridgedClass(MTrackBridge.bridgedClass, lib);

      // MProvider base class
      interpreter.registerBridgedClass(MProviderBridge.bridgedClass, lib);

      // Enums
      interpreter.registerBridgedEnum(MangaStatusBridge.bridgedEnum, lib);

      // Filters
      interpreter.registerBridgedClass(FilterListBridge.bridgedClass, lib);
      interpreter.registerBridgedClass(SelectFilterBridge.bridgedClass, lib);
      interpreter.registerBridgedClass(CheckBoxFilterBridge.bridgedClass, lib);
      interpreter.registerBridgedClass(GroupFilterBridge.bridgedClass, lib);

      // Preferences
      interpreter.registerBridgedClass(SourcePreferenceBridge.bridgedClass, lib);
      interpreter.registerBridgedClass(
          SourcePreferenceEntryBridge.bridgedClass, lib);

      // Top-level utility functions
      MProviderUtilities.register(interpreter, lib);
    }
  }
}
