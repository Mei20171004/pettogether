import SwiftUI

@main
struct CopawApp: App {
    @UIApplicationDelegateAdaptor(FirebaseAppDelegate.self) private var appDelegate
    @StateObject private var store: CareStore
    @StateObject private var language = AppLanguageStore()

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--copaw-demo-reset-session") {
            UserDefaults.standard.removeObject(forKey: "copaw.activeHouseholdID")
            UserDefaults.standard.set("en", forKey: "copaw.language")
            UserDefaults.standard.synchronize()
        } else if let index = arguments.firstIndex(of: "--copaw-demo-household"),
                  arguments.indices.contains(index + 1) {
            UserDefaults.standard.set(arguments[index + 1], forKey: "copaw.activeHouseholdID")
            UserDefaults.standard.set("en", forKey: "copaw.language")
            UserDefaults.standard.synchronize()
        }
        #endif
        _store = StateObject(
            wrappedValue: CareStore(service: FirebaseCareService())
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(language)
                .tint(Color.pawPurple)
                .task {
                    await store.restoreSession()
                }
        }
    }
}
