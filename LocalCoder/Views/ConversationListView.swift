import SwiftUI

struct ConversationListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var store = ConversationStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.summaries.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .background(LC.surface)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("HISTORY")
                        .font(LC.label(12))
                        .tracking(2)
                        .foregroundStyle(LC.primary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundStyle(LC.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        viewModel.newConversation()
                        dismiss()
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(LC.accent)
                    }
                }
            }
            .toolbarBackground(LC.surfaceElevated, for: .navigationBar)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: LC.spacingMD) {
            Spacer()

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 36, weight: .thin, design: .monospaced))
                .foregroundStyle(LC.secondary.opacity(0.5))

            Text("NO CONVERSATIONS")
                .font(LC.label(11))
                .tracking(1.5)
                .foregroundStyle(LC.secondary)

            Text("Start chatting to create your first conversation.")
                .font(LC.caption(12))
                .foregroundStyle(LC.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, LC.spacingXL)

            Spacer()
        }
    }

    // MARK: - List

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.summaries) { summary in
                    ConversationRow(
                        summary: summary,
                        isActive: viewModel.activeConversation?.id == summary.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.loadConversation(id: summary.id)
                        dismiss()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteConversation(id: summary.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    Rectangle()
                        .fill(LC.border)
                        .frame(height: LC.borderWidth)
                }
            }
        }
    }
}

// MARK: - Row

private struct ConversationRow: View {
    let summary: ConversationStore.ConversationSummary
    let isActive: Bool

    var body: some View {
        HStack(spacing: LC.spacingSM) {
            // Active indicator
            Circle()
                .fill(isActive ? LC.accent : .clear)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: LC.spacingXS) {
                Text(summary.title)
                    .font(LC.body(13))
                    .foregroundStyle(LC.primary)
                    .lineLimit(1)

                HStack(spacing: LC.spacingSM) {
                    Text(relativeDate(summary.updatedAt))
                        .font(LC.caption(10))
                        .foregroundStyle(LC.secondary)

                    Text("·")
                        .font(LC.caption(10))
                        .foregroundStyle(LC.secondary.opacity(0.5))

                    Text("\(summary.messageCount) MSG")
                        .font(LC.label(9))
                        .tracking(1)
                        .foregroundStyle(LC.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(LC.secondary.opacity(0.4))
        }
        .padding(.horizontal, LC.spacingMD)
        .padding(.vertical, LC.spacingSM + 2)
        .background(isActive ? LC.accent.opacity(0.06) : LC.surface)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
