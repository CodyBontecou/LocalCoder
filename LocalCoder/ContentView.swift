import SwiftUI

struct ContentView: View {
    @EnvironmentObject var llmService: LLMService
    @State private var selectedTab: LCTab = .chat

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .chat:
                    ChatView()
                case .files:
                    FilesView()
                case .git:
                    GitView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LCTabBar(selectedTab: $selectedTab)
        }
        .background(LC.surface)
        .tint(LC.accent)
        .task {
            await llmService.autoLoadLastModel()
        }
    }
}
