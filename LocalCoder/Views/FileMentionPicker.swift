import SwiftUI

/// A dropdown picker for selecting files/folders via "@" mention.
struct FileMentionPicker: View {
    let files: [FileItem]
    let filter: String
    let onSelect: (FileItem) -> Void
    let onDismiss: () -> Void

    /// Filtered files based on the current filter text.
    private var filteredFiles: [FileItem] {
        if filter.isEmpty {
            return Array(files.prefix(20))
        }
        let lowercased = filter.lowercased()
        return files.filter { item in
            item.name.lowercased().contains(lowercased) ||
            item.path.lowercased().contains(lowercased)
        }.prefix(20).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            if filteredFiles.isEmpty {
                HStack {
                    Text("No matches")
                        .font(LC.caption(12))
                        .foregroundStyle(LC.secondary)
                    Spacer()
                }
                .padding(LC.spacingSM)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredFiles) { file in
                            FileMentionRow(file: file)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(file)
                                }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .background(LC.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: LC.radiusMD))
        .overlay(
            RoundedRectangle(cornerRadius: LC.radiusMD)
                .stroke(LC.border, lineWidth: LC.borderWidth)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

/// A single row in the file mention picker.
struct FileMentionRow: View {
    let file: FileItem

    /// Relative path for display (strips common prefixes).
    private var displayPath: String {
        let components = file.path.components(separatedBy: "/")
        // Show last 2-3 path components for context
        let relevant = components.suffix(3)
        return relevant.joined(separator: "/")
    }

    var body: some View {
        HStack(spacing: LC.spacingSM) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 12))
                .foregroundStyle(file.isDirectory ? LC.accent : LC.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(LC.body(13))
                    .foregroundStyle(LC.primary)
                    .lineLimit(1)

                Text(displayPath)
                    .font(LC.caption(10))
                    .foregroundStyle(LC.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, LC.spacingSM)
        .padding(.vertical, 6)
        .background(LC.surfaceElevated)
        .contentShape(Rectangle())
    }
}

/// A chip showing the currently focused file.
struct FocusedFileChip: View {
    let file: FileItem
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 9))
                .foregroundStyle(LC.accent)

            Text(file.name)
                .font(LC.label(10))
                .tracking(0.5)
                .foregroundStyle(LC.primary)
                .lineLimit(1)

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(LC.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(LC.accent.opacity(0.15))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(LC.accent.opacity(0.3), lineWidth: LC.borderWidth)
        )
    }
}

#Preview {
    VStack {
        FileMentionPicker(
            files: [
                FileItem(name: "ContentView.swift", path: "/project/ContentView.swift", isDirectory: false, children: nil),
                FileItem(name: "Models", path: "/project/Models", isDirectory: true, children: []),
                FileItem(name: "ChatViewModel.swift", path: "/project/ViewModels/ChatViewModel.swift", isDirectory: false, children: nil),
            ],
            filter: "",
            onSelect: { _ in },
            onDismiss: {}
        )
        .padding()

        FocusedFileChip(
            file: FileItem(name: "ChatView.swift", path: "/test", isDirectory: false, children: nil),
            onClear: {}
        )
    }
    .background(LC.surface)
}
