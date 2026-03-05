import SwiftUI

struct ContentView: View {
    @EnvironmentObject var llmService: LLMService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.text.bubble.right")
                }
                .tag(0)

            FilesView()
                .tabItem {
                    Label("Files", systemImage: "folder")
                }
                .tag(1)

            GitView()
                .tabItem {
                    Label("Git", systemImage: "arrow.triangle.branch")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .tint(.green)
    }
}
