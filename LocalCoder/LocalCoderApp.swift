import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct LocalCoderApp: App {
    @StateObject private var llmService = LLMService.shared
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var workingDir = WorkingDirectoryService.shared
    @StateObject private var gitSync = GitSyncManager.shared
    @StateObject private var gitHubAuth = GitHubAuthService.shared
    @StateObject private var debugConsole = DebugConsole.shared

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(llmService)
                .environmentObject(modelManager)
                .environmentObject(workingDir)
                .environmentObject(gitSync)
                .environmentObject(gitHubAuth)
                .environmentObject(debugConsole)
        }
    }
}

#if canImport(UIKit)
/// Minimal AppDelegate to handle system-level memory warnings.
/// `LLMService` also listens for the notification independently, but having the
/// delegate ensures the app participates in the standard iOS memory-warning lifecycle.
class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        DebugConsole.shared.log(
            "App-level memory warning received",
            category: .app,
            level: .warning
        )
        // LLMService handles the actual cleanup via NotificationCenter
    }
}
#endif
