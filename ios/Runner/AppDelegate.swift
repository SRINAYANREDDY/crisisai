import UIKit
import Flutter
import GoogleMaps          // ← ADD THIS IMPORT
import UserNotifications

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // ── Google Maps iOS SDK initialisation ────────────────────────────
        // IMPORTANT: Replace YOUR_GOOGLE_MAPS_API_KEY with your actual key.
        // Steps to get an iOS key:
        //   1. Go to https://console.cloud.google.com/
        //   2. Enable "Maps SDK for iOS"
        //   3. Create an API Key under Credentials
        //   4. Restrict it to your Bundle ID (e.g. com.example.crisisAi)
        //   5. Paste it below (between the quotes)
        GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")

        // FCM notification delegate
        UNUserNotificationCenter.current().delegate = self

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}