import SwiftUI

struct WelcomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LC.spacingSM) {
                Group {
                    Text("$ localcoder --help")
                        .foregroundStyle(LC.accent)
                    
                    Text("")
                    
                    Text("LOCALCODER v1.0")
                        .foregroundStyle(LC.primary)
                    Text("On-device AI coding assistant")
                        .foregroundStyle(LC.secondary)
                    
                    Text("")
                    
                    Text("TOOLS:")
                        .foregroundStyle(LC.secondary)
                    Text("  read <file>      Read file contents")
                    Text("  write <file>     Create or overwrite file")
                    Text("  edit <file>      Make precise changes")
                    Text("  bash <cmd>       Run shell command")
                }
                
                Group {
                    Text("")
                    
                    Text("USAGE:")
                        .foregroundStyle(LC.secondary)
                    
                    HStack(spacing: 0) {
                        Text("  1. ")
                        Button("Load a model") {
                            NotificationCenter.default.post(name: .openModelManager, object: nil)
                        }
                        .foregroundStyle(LC.accent)
                    }
                    
                    Text("  2. Open a project folder")
                    Text("  3. Ask anything")
                    
                    Text("")
                    
                    Text("EXAMPLES:")
                        .foregroundStyle(LC.secondary)
                    Text("  \"List all Swift files\"")
                        .foregroundStyle(LC.secondary)
                    Text("  \"Create a new view\"")
                        .foregroundStyle(LC.secondary)
                    Text("  \"Fix the bug in Main.swift\"")
                        .foregroundStyle(LC.secondary)
                    
                    Text("")
                    
                    Text("Ready for input...")
                        .foregroundStyle(LC.secondary)
                        .opacity(0.6)
                }
            }
            .font(LC.code(13))
            .foregroundStyle(LC.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LC.spacingMD)
        }
        .background(LC.surface)
    }
}

// MARK: - Navigation Notification

extension Notification.Name {
    static let navigateToTab = Notification.Name("navigateToTab")
    static let openModelManager = Notification.Name("openModelManager")
}

#Preview {
    WelcomeView()
}
