import FirebaseCore
import UIKit

final class FirebaseAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard Bundle.main.path(
            forResource: "GoogleService-Info",
            ofType: "plist"
        ) != nil else {
            return true
        }

        FirebaseApp.configure()
        return true
    }
}
