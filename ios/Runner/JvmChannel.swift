import Flutter
import Foundation

#if FOXLATIONS_JVM

// M5.1: registers the `foxlations/jvm` MethodChannel that bridges Dart to the embedded
// OpenJDK Zero VM. For now it exposes a single `probe` method (boot the VM + run the
// Suwayomi-hosted MangaDex fetch self-test) so we can confirm the whole stack works
// inside the real Foxlations app. M5.2 will add getPopular/getDetail/getPageList/… .
//
// Compiled only in the -DFOXLATIONS_JVM build; JvmChannel.swift is not part of the
// normal Runner target, and AppDelegate's call to registerFoxJvmChannel is #if-gated.
func registerFoxJvmChannel(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "foxlations.jvm") else { return }
    let channel = FlutterMethodChannel(name: "foxlations/jvm", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
        switch call.method {
        case "probe":
            // FoxJvmProbeAsync boots on a large-stack worker thread and calls back on the
            // main queue, so it's safe to hand the report straight to `result`.
            FoxJvmProbeAsync { report in
                result(report)
            }
        case "invoke":
            // A JSON request string ({method, jar, lang?, page?, query?, url?}); the JSON
            // response is handed back to Dart, which parses it into the app models.
            guard let req = call.arguments as? String else {
                result(FlutterError(code: "bad_args", message: "invoke expects a JSON string", details: nil))
                return
            }
            FoxJvmInvokeAsync(req) { response in
                result(response)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

#endif
