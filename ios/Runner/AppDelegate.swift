import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    guard
      let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String,
      !mapsApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !mapsApiKey.contains("$(")
    else {
      fatalError(
        "Missing GOOGLE_MAPS_API_KEY. Set it in an ignored iOS xcconfig file or Xcode build settings."
      )
    }

    GMSServices.provideAPIKey(mapsApiKey)
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
