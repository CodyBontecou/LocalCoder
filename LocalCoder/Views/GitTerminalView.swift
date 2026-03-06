import SwiftUI

struct GitTerminalView: View {
    let output: [String]
    let isLoading: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(output.enumerated()), id: \.offset) { index, line in
                        Text(coloredLine(line))
                            .font(LC.code(12))
                            .textSelection(.enabled)
                            .id(index)
                    }

                    if isLoading {
                        HStack(spacing: LC.spacingSM) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(LC.accent)
                            Text("WORKING...")
                                .font(LC.label(9))
                                .tracking(1.5)
                                .foregroundStyle(LC.accent)
                        }
                        .id("loading")
                    }
                }
                .padding(LC.spacingMD)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(LC.inverseSurface)
            .onChange(of: output.count) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(output.count - 1, anchor: .bottom)
                }
            }
        }
    }

    private func coloredLine(_ line: String) -> AttributedString {
        var attributed = AttributedString(line)

        if line.hasPrefix("$") {
            attributed.foregroundColor = UIColor(LC.accent)
        } else if line.hasPrefix("✅") {
            attributed.foregroundColor = UIColor(LC.accent)
        } else if line.hasPrefix("❌") || line.lowercased().contains("error") {
            attributed.foregroundColor = UIColor(LC.destructive)
        } else if line.hasPrefix("  ") && (line.contains("Downloading") || line.contains("Creating")) {
            attributed.foregroundColor = UIColor(LC.secondary)
        } else if line.hasPrefix("╔") || line.hasPrefix("║") || line.hasPrefix("╠") || line.hasPrefix("╚") {
            attributed.foregroundColor = UIColor(LC.accent)
        } else {
            // Use surface color (which is light in dark mode context of inverseSurface bg)
            attributed.foregroundColor = UIColor(LC.surface)
        }

        return attributed
    }
}
