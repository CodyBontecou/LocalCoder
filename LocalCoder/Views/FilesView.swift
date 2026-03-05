import SwiftUI

struct FilesView: View {
    @StateObject private var viewModel = FilesViewModel()
    @State private var showNewFileAlert = false
    @State private var showNewFolderAlert = false
    @State private var newItemName = ""
    @State private var showRenameAlert = false
    @State private var renamingItem: FileItem?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.files.isEmpty {
                    emptyState
                } else {
                    fileList
                }
            }
            .navigationTitle(viewModel.isAtRoot ? "Projects" : viewModel.currentDirName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.isAtRoot {
                        Button(action: { viewModel.navigateBack() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { showNewFileAlert = true }) {
                            Label("New File", systemImage: "doc.badge.plus")
                        }
                        Button(action: { showNewFolderAlert = true }) {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New File", isPresented: $showNewFileAlert) {
                TextField("filename.swift", text: $newItemName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Create") {
                    viewModel.createNewFile(name: newItemName)
                    newItemName = ""
                }
                Button("Cancel", role: .cancel) { newItemName = "" }
            }
            .alert("New Folder", isPresented: $showNewFolderAlert) {
                TextField("Folder name", text: $newItemName)
                    .autocorrectionDisabled()
                Button("Create") {
                    viewModel.createNewFolder(name: newItemName)
                    newItemName = ""
                }
                Button("Cancel", role: .cancel) { newItemName = "" }
            }
            .alert("Rename", isPresented: $showRenameAlert) {
                TextField("New name", text: $newItemName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Rename") {
                    if let item = renamingItem {
                        viewModel.renameItem(item, to: newItemName)
                    }
                    newItemName = ""
                }
                Button("Cancel", role: .cancel) { newItemName = "" }
            }
            .sheet(isPresented: $viewModel.isEditing) {
                CodeEditorView(
                    filename: URL(fileURLWithPath: viewModel.selectedFile ?? "").lastPathComponent,
                    content: $viewModel.fileContent,
                    onSave: { viewModel.saveFile() },
                    onDismiss: { viewModel.isEditing = false }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: viewModel.isAtRoot ? "folder.badge.questionmark" : "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(viewModel.isAtRoot ? "No Projects Yet" : "Empty Folder")
                .font(.title3.bold())

            Text(viewModel.isAtRoot ? "Generate code from Chat or clone from Git" : "Create files or generate code to fill this folder")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var fileList: some View {
        List {
            ForEach(viewModel.files) { item in
                Button(action: { viewModel.navigateTo(item) }) {
                    HStack(spacing: 12) {
                        Image(systemName: iconFor(item))
                            .font(.title3)
                            .foregroundStyle(colorFor(item))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.body)
                                .foregroundStyle(.primary)

                            if item.isDirectory {
                                let count = (try? FileManager.default.contentsOfDirectory(atPath: item.path))?.count ?? 0
                                Text("\(count) items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if item.isDirectory {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.deleteItem(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        renamingItem = item
                        newItemName = item.name
                        showRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.refresh()
        }
    }

    private func iconFor(_ item: FileItem) -> String {
        if item.isDirectory { return "folder.fill" }
        let ext = URL(fileURLWithPath: item.name).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "text.page"
        case "js", "ts": return "j.square"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush"
        case "json": return "curlybraces"
        case "md": return "doc.richtext"
        case "yaml", "yml": return "list.bullet.indent"
        case "sh": return "terminal"
        case "gitignore": return "eye.slash"
        default: return "doc.text"
        }
    }

    private func colorFor(_ item: FileItem) -> Color {
        if item.isDirectory { return .blue }
        let ext = URL(fileURLWithPath: item.name).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "py": return .blue
        case "js": return .yellow
        case "ts": return .blue
        case "html": return .red
        case "css": return .purple
        case "json": return .green
        default: return .secondary
        }
    }
}
