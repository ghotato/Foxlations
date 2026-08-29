import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // media_kit never touches AVAudioSession, so iOS leaves us on the default
    // .soloAmbient category — video audio is muted by the hardware Ring/Silent
    // switch and playback stops the moment the app is backgrounded. Neither
    // happens on Android, so it reads as "video is broken" on iOS.
    // Requires the `audio` entry in UIBackgroundModes (Info.plist).
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    try? AVAudioSession.sharedInstance().setActive(true)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    #if FOXLATIONS_JVM
    // Embedded-JVM channel for Kotlin extensions. Only present in the JVM build
    // (the -DFOXLATIONS_JVM configuration); a no-op in the normal production build.
    registerFoxJvmChannel(engineBridge.pluginRegistry)
    #endif
  }
}
