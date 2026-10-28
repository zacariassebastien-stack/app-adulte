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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GameMediaCapabilities") else { return }
    let channel = FlutterMethodChannel(name: "couple_cards/media_capabilities", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "captureCapabilities" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let types = UIImagePickerController.isSourceTypeAvailable(.camera)
        ? (UIImagePickerController.availableMediaTypes(for: .camera) ?? []) : []
      var capabilities: [String] = []
      if types.contains("public.image") { capabilities.append("PHOTO_CAPTURE") }
      if types.contains("public.movie") { capabilities.append("RECORDED_VIDEO") }
      result(capabilities)
    }
  }
}
