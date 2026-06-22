import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ── ต้องใส่ API Key ของ Google Maps ที่นี่ ไม่เช่นนั้นแผนที่บน iOS จะแสดงเป็นสีเทาๆ (กระดานเปล่า) ──
    // ใช้ key เดียวกันกับที่ตั้งไว้ใน AndroidManifest.xml (แนะนำให้สร้าง iOS API key แยกต่างหากใน Google Cloud Console
    // แล้วเปิดใช้งาน "Maps SDK for iOS" สำหรับ key นั้น)
    GMSServices.provideAPIKey("AIzaSyBhmpBpL6rsu2CFxp_-AnpA_KyUa3pLvbs")

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}