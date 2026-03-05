import SwiftUI

struct GitTerminalView: View {
    let output: [String]
    let isLoading: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(output.enumerated()), id: \.offset) { index, line in
                        Text(coloredLine(line))
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .id(index)
                    }

                    if isLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Working...")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.yellow)
                        }
                        .id("loading")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black)
            .onChange(of: output.count) { _, _ in
                withAnimation {
                    proxy.scrollTo(output.count - 1, anchor: .bottom)
                }
            }
        }
    }

    private func coloredLine(_ line: String) -> AttributedString {
        var attributed = AttributedString(line)

        if line.hasPrefix("$") {
            attributed.foregroundColor = .green
        } else if line.hasPrefix("✅") {
            attributed.foregroundColor = .green
        } else if line.hasPrefix("❌") || line.lowercased().contains("error") {
            attributed.foregroundColor = .red
        } else if line.hasPrefix("  ") && (line.contains("Downloading") || line.contains("Creating")) {
            attributed.foregroundColor = .cyan
        } else if line.contains("🔒") || line.contains("🌐") {
            attributed.foregroundColor = .white
        } else if line.hasPrefix("╔") || line.hasPrefix("║") || line.hasPrefix("╠") || line.hasPrefix("╚") {
            attributed.foregroundColor = .cyan
        } else {
            attributed.foregroundColor = .white.opacity(0.85)
        }

        return attributed
    }
}
