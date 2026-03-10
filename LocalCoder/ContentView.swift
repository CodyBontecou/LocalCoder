import SwiftUI

struct ContentView: View {
    @EnvironmentObject var llmService: LLMService
    @State private var selectedTab: LCTab = .chat
    @State private var chatInputFocused = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .chat:
                    ChatView(isInputFocused: $chatInputFocused)
                case .files:
                    FilesView()
                case .git:
                    GitView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LCAccessoryBar(selectedTab: $selectedTab, isKeyboardActive: $chatInputFocused)
        }
        .background(LC.surface.ignoresSafeArea())
        .tint(LC.accent)
        .task {
            await llmService.autoLoadLastModel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTab)) { notification in
            if let tab = notification.object as? LCTab {
                selectedTab = tab
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openModelManager)) { _ in
            selectedTab = .settings
        }
    }
}
