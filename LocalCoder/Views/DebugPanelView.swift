import SwiftUI
#if os(iOS)
import UIKit
#endif

struct DebugPanelView: View {
    @ObservedObject var console: DebugConsole
    @Binding var isExpanded: Bool
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                Rectangle().fill(LC.border).frame(height: LC.borderWidth)

                statsRow

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: LC.spacingSM) {
                            if console.entries.isEmpty {
                                Text("No debug events yet.")
                                    .font(LC.caption(11))
                                    .foregroundStyle(LC.secondary)
                                    .padding(.top, LC.spacingMD)
                            } else {
                                ForEach(console.entries) { entry in
                                    DebugLogRow(entry: entry)
                                        .id(entry.id)
                                }
                            }
                        }
                        .padding(LC.spacingSM + 2)
                    }
                    .frame(maxHeight: 220)
                    .onAppear {
                        scrollToBottom(using: proxy)
                    }
                    .onChange(of: console.latestEntry?.id) { _, _ in
                        guard autoScroll else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            scrollToBottom(using: proxy)
                        }
                    }
                }
            }
        }
        .background(LC.inverseSurface)
        .clipShape(RoundedRectangle(cornerRadius: LC.radiusMD))
        .overlay(
            RoundedRectangle(cornerRadius: LC.radiusMD)
                .stroke(console.errorCount > 0 ? LC.destructive.opacity(0.5) : LC.border, lineWidth: LC.borderWidth)
        )
        .padding(.horizontal, LC.spacingMD)
        .padding(.top, LC.spacingSM)
        .padding(.bottom, LC.spacingXS)
    }

    private var header: some View {
        HStack(spacing: LC.spacingSM) {
            LCStatusDot(isActive: console.errorCount == 0)

            VStack(alignment: .leading, spacing: 2) {
                Text("DEBUG")
                    .font(LC.label(9))
                    .tracking(1.5)
                    .foregroundStyle(LC.surface)

                Text(console.latestEntry?.message ?? "Watching events")
                    .font(LC.caption(10))
                    .foregroundStyle(LC.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if console.errorCount > 0 {
                Text("\(console.errorCount) ERR")
                    .font(LC.label(9))
                    .tracking(1)
                    .foregroundStyle(LC.destructive)
            }

            Button(action: copyLogs) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LC.secondary)
            }
            .buttonStyle(.plain)

            Button(action: { console.clear() }) {
                Image(systemName: "trash")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LC.secondary)
            }
            .buttonStyle(.plain)

            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(LC.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LC.spacingMD - 4)
        .padding(.vertical, LC.spacingSM + 2)
    }

    private var statsRow: some View {
        HStack(spacing: LC.spacingSM) {
            statChip("EVENTS", "\(console.entries.count)")
            statChip("ERRORS", "\(console.errorCount)")

            Spacer()

            Toggle("", isOn: $autoScroll)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.7)
                .tint(LC.accent)

            Text("AUTO")
                .font(LC.label(8))
                .tracking(1)
                .foregroundStyle(LC.secondary)
        }
        .padding(.horizontal, LC.spacingMD - 4)
        .padding(.vertical, LC.spacingSM)
    }

    private func statChip(_ title: String, _ value: String) -> some View {
        HStack(spacing: LC.spacingXS) {
            Text(title)
                .font(LC.label(8))
                .tracking(1)
                .foregroundStyle(LC.secondary)
            Text(value)
                .font(LC.label(10))
                .foregroundStyle(LC.surface)
        }
        .padding(.horizontal, LC.spacingSM)
        .padding(.vertical, LC.spacingXS)
        .background(LC.surface.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        if let latest = console.latestEntry {
            proxy.scrollTo(latest.id, anchor: .bottom)
        }
    }

    private func copyLogs() {
        #if os(iOS)
        UIPasteboard.general.string = console.exportText()
        #endif
    }
}

private struct DebugLogRow: View {
    let entry: DebugLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: LC.spacingXS) {
            HStack(spacing: LC.spacingSM) {
                Text(entry.timestampLabel)
                    .font(LC.caption(9))
                    .foregroundStyle(LC.secondary)

                Text(entry.category.rawValue.uppercased())
                    .font(LC.label(8))
                    .tracking(1)
                    .foregroundStyle(LC.accent)

                Text(entry.level.rawValue.uppercased())
                    .font(LC.label(8))
                    .tracking(1)
                    .foregroundStyle(levelColor)
            }

            Text(entry.message)
                .font(LC.code(11))
                .foregroundStyle(LC.surface)
                .textSelection(.enabled)

            if let details = entry.details, !details.isEmpty {
                Text(details)
                    .font(LC.code(10))
                    .foregroundStyle(LC.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LC.spacingSM)
        .background(LC.surface.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return LC.secondary
        case .info: return LC.accent
        case .warning: return LC.accent
        case .error: return LC.destructive
        }
    }
}
