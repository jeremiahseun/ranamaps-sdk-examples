import RanaMapsSDK
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Same mechanism as RanaMapsSample: public key from the RANA_KEY environment variable
        // (Xcode scheme, or `SIMCTL_CHILD_RANA_KEY=... xcrun simctl launch ...`).
        do { try RanaMaps.configure(apiKey: ProcessInfo.processInfo.environment["RANA_KEY"] ?? Bundle.main.object(forInfoDictionaryKey: "RanaMapsAPIKey") as? String ?? "pk_live_replace_me") }
        catch { print("Rana Maps configuration failed: \((error as? RanaError)?.code ?? "unknown")") }
        return true
    }
}

@main
struct RideHailSampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { WindowGroup { RideHailView() } }
}
