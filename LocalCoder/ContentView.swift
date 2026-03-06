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

            LCAccessoryBar(selectedTab: $selectedTab, onDismissKeyboard: {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
        }
        .background(LC.surface.ignoresSafeArea())
        .tint(LC.accent)
        .task {
            await llmService.autoLoadLastModel()
        }
    }
}
