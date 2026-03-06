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
            .background(LC.surface)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.isAtRoot ? "FILES" : viewModel.currentDirName.uppercased())
                        .font(LC.label(12))
                        .tracking(2)
                        .foregroundStyle(LC.primary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.isAtRoot {
                        Button(action: { viewModel.navigateBack() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                Text("BACK")
                                    .font(LC.label(10))
                                    .tracking(1)
                            }
                            .foregroundStyle(LC.accent)
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
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundStyle(LC.accent)
                    }
                }
            }
            .toolbarBackground(LC.surfaceElevated, for: .navigationBar)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: LC.spacingMD) {
            Image(systemName: viewModel.isAtRoot ? "folder" : "doc.text")
                .font(.system(size: 32, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(LC.secondary)

            Text(viewModel.isAtRoot ? "NO PROJECTS" : "EMPTY")
                .font(LC.heading(16))
                .foregroundStyle(LC.primary)

            Text(viewModel.isAtRoot ? "Generate code from Chat\nor clone from Git" : "Create files or generate code")
                .font(LC.caption(12))
                .foregroundStyle(LC.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - File List

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.files) { item in
                    Button(action: { viewModel.navigateTo(item) }) {
                        fileRow(item)
                    }
                    .buttonStyle(.plain)
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
                        .tint(LC.accent)
                    }
                }
            }
            .padding(.horizontal, LC.spacingMD)
            .padding(.top, LC.spacingSM)
        }
        .refreshable {
            viewModel.refresh()
        }
    }

    private func fileRow(_ item: FileItem) -> some View {
        HStack(spacing: LC.spacingMD - 4) {
            // File type indicator — small square with extension
            ZStack {
                RoundedRectangle(cornerRadius: LC.radiusSM)
                    .fill(item.isDirectory ? LC.accent.opacity(0.12) : LC.border.opacity(0.3))
                    .frame(width: 32, height: 32)

                if item.isDirectory {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(LC.accent)
                } else {
                    Text(extLabel(item.name))
                        .font(LC.label(8))
                        .tracking(0.5)
                        .foregroundStyle(LC.primary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(LC.body(13))
                    .foregroundStyle(LC.primary)
                    .lineLimit(1)

                if item.isDirectory {
                    let count = (try? FileManager.default.contentsOfDirectory(atPath: item.path))?.count ?? 0
                    Text("\(count) items")
                        .font(LC.caption(10))
                        .foregroundStyle(LC.secondary)
                }
            }

            Spacer()

            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(LC.secondary)
            }
        }
        .padding(.vertical, LC.spacingSM + 2)
        .padding(.horizontal, LC.spacingSM)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(LC.border.opacity(0.5)).frame(height: LC.borderWidth)
        }
    }

    private func extLabel(_ name: String) -> String {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        if ext.isEmpty { return "·" }
        return ext.prefix(3).uppercased()
    }
}
