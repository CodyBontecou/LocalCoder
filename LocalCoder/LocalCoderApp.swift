import SwiftUI

@main
struct LocalCoderApp: App {
    @StateObject private var llmService = LLMService.shared
    @StateObject private var modelManager = ModelManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(llmService)
                .environmentObject(modelManager)
        }
    }
}
