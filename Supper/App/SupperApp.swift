import SwiftUI
import CloudKit

@main
struct SupperApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = RecipeStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.primary)
                .preferredColorScheme(uiTestColorScheme)
                .environmentObject(store)
                .task { await store.load() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, store.isReady { Task { await store.checkCloudAccount() } }
                }
        }
    }
    private var uiTestColorScheme: ColorScheme? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") && arguments.contains("--ui-testing-dark") { return .dark }
        #endif
        return nil
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--ui-testing-disable-animations") {
            // Menu action tests don't need to wait for the system's glass hover animation.
            UIView.setAnimationsEnabled(false)
        }
        if ProcessInfo.processInfo.arguments.contains("--discovery-ui-testing") {
            UserDefaults.standard.set(false, forKey: "discoveryGridView")
        }
        #endif
        if RecipeStore.shared.persistence.cloudEnabled { application.registerForRemoteNotifications() }
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareSceneDelegate.self
        if let metadata = options.cloudKitShareMetadata { RecipeStore.shared.receiveInvitation(metadata) }
        return configuration
    }
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        RecipeStore.shared.receiveInvitation(cloudKitShareMetadata)
    }
}
final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        RecipeStore.shared.receiveInvitation(cloudKitShareMetadata)
    }
}
