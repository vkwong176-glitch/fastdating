import AudioToolbox
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 與 Android MainActivity 相同 channel：App 內偵測新訊息時播放可聽見的系統聲
    // （Dart 層 SystemSoundType.alert 在部分情境近乎無聲，改走原生系統音）
    let messageSound = FlutterMethodChannel(
      name: "app.message_sound",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    messageSound.setMethodCallHandler { call, result in
      if call.method == "playDefaultNotification" {
        // 1007：常見的「新訊息」提示音（與內建訊息鈴聲未必相同，但可穩定聽到聲響）
        AudioServicesPlaySystemSound(1007)
        result.success(nil)
      } else {
        result.notImplemented()
      }
    }
  }
}
