import SwiftUI

@main
struct LocalCoderApp: App {
    @StateObject private var llmService = LLMService.shared
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var workingDir = WorkingDirectoryService.shared
    @StateObject private var gitSync = GitSyncManager.shared
    @StateObject private var gitHubAuth = GitHubAuthService.shared
    @StateObject private var debugConsole = DebugConsole.shared

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
