import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var llmService: LLMService
    @EnvironmentObject var debugConsole: DebugConsole
    @AppStorage("show_debug_console") private var showDebugConsole = false
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var workingDir = WorkingDirectoryService.shared
    @StateObject private var gitSync = GitSyncManager.shared
    @State private var showSaveSheet = false
    @State private var selectedCodeBlock: CodeBlock?
    @State private var saveFilename = ""
    @State private var saveProject = ""
    @State private var showFolderPicker = false
    @State private var isDebugPanelExpanded = true
    @State private var showConversationList = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status strip
                statusStrip

                // Working directory
                directoryStrip

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: LC.spacingMD) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message, onSaveCode: { block in
                                    selectedCodeBlock = block
                                    saveFilename = block.filename ?? "code.\(extensionFor(block.language))"
                                    showSaveSheet = true
                                })
                                .id(message.id)
                            }
                        }
                        .padding(LC.spacingMD)
                    }
                    .background(LC.surface)
                    .onChange(of: viewModel.messages.last?.content) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Error banner
                if let error = viewModel.error {
                    HStack(spacing: LC.spacingSM) {
                        Text("ERR")
                            .font(LC.label(10))
                            .tracking(1.5)
                            .foregroundStyle(LC.destructive)

                        Rectangle()
                            .fill(LC.destructive.opacity(0.3))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                            .padding(.vertical, 4)

                        Text(error)
                            .font(LC.caption(11))
                            .foregroundStyle(LC.primary)
                            .lineLimit(2)

                        Spacer()

                        Button(action: { viewModel.error = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(LC.secondary)
                        }
                    }
                    .padding(.horizontal, LC.spacingMD)
                    .padding(.vertical, LC.spacingSM)
                    .background(LC.destructive.opacity(0.08))
                    .overlay(alignment: .top) {
                        Rectangle().fill(LC.destructive.opacity(0.4)).frame(height: 1)
                    }
                }

                if showDebugConsole {
                    DebugPanelView(console: debugConsole, isExpanded: $isDebugPanelExpanded)
                }

                // Input
                inputBar
            }
            .background(LC.surface.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSaveSheet) {
                saveCodeSheet
            }
            .sheet(isPresented: $showConversationList) {
                ConversationListView(viewModel: viewModel)
            }
            
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        workingDir.setWorkingDirectory(url)
                    }
                case .failure(let error):
                    viewModel.error = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Status Strip

    private var statusStrip: some View {
        HStack(spacing: LC.spacingSM) {
            LCStatusDot(isActive: llmService.isModelLoaded)

            Text(llmService.isModelLoaded ? "READY" : "NO MODEL")
                .font(LC.label(9))
                .tracking(1.5)
                .foregroundStyle(llmService.isModelLoaded ? LC.accent : LC.secondary)

            Spacer()

            if viewModel.isGenerating {
                HStack(spacing: LC.spacingXS) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(LC.accent)
                    Text("GENERATING")
                        .font(LC.label(9))
                        .tracking(1.5)
                        .foregroundStyle(LC.accent)
                }
            }
        }
        .padding(.horizontal, LC.spacingMD)
        .padding(.vertical, 6)
        .background(Color(red: 0.965, green: 0.949, blue: 0.925)) // #F6F2EC
    }

    // MARK: - Directory Strip

    private var directoryStrip: some View {
        HStack(spacing: LC.spacingSM) {
            if gitSync.hasActiveRepo {
                // Show active git repo
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(LC.accent)

                Text(gitSync.activeRepoName)
                    .font(LC.caption(11))
                    .foregroundStyle(LC.primary)
                    .lineLimit(1)

                Text(gitSync.activeRepoBranch)
                    .font(LC.label(8))
                    .tracking(1)
                    .foregroundStyle(LC.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(LC.surface)
                    .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))

                Spacer()
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(workingDir.workingDirectoryURL != nil ? LC.accent : LC.secondary)

                if workingDir.workingDirectoryURL != nil {
                    Text(workingDir.workingDirectoryName)
                        .font(LC.caption(11))
                        .foregroundStyle(LC.primary)
                        .lineLimit(1)

                    Spacer()

                    Button(action: { workingDir.clearWorkingDirectory() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(LC.secondary)
                    }
                } else {
                    Text("NO PROJECT")
                        .font(LC.label(9))
                        .tracking(1)
                        .foregroundStyle(LC.secondary)
                    Spacer()
                }

                Button(action: { showFolderPicker = true }) {
                    Text(workingDir.workingDirectoryURL != nil ? "CHANGE" : "OPEN")
                        .font(LC.label(9))
                        .tracking(1)
                        .foregroundStyle(LC.accent)
                }
            }
        }
        .padding(.horizontal, LC.spacingMD)
        .padding(.vertical, 5)
        .background(Color(red: 0.965, green: 0.949, blue: 0.925)) // #F6F2EC
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: LC.spacingSM) {
            TextField("Ask for code...", text: $viewModel.inputText, axis: .vertical)
                .font(LC.body(14))
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(LC.spacingSM + 2)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                .onSubmit {
                    if !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        viewModel.sendMessage()
                    }
                }

            Button(action: {
                if viewModel.isGenerating {
                    viewModel.stopGenerating()
                } else {
                    viewModel.sendMessage()
                }
            }) {
                Image(systemName: viewModel.isGenerating ? "stop.fill" : "arrow.up")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(viewModel.isGenerating ? .white : .white)
                    .frame(width: 36, height: 36)
                    .background(viewModel.isGenerating ? LC.destructive : LC.accent)
                    .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
            }
            .disabled(!viewModel.isGenerating && (viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !llmService.isModelLoaded))
            .opacity(!viewModel.isGenerating && (viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !llmService.isModelLoaded) ? 0.35 : 1)
        }
        .padding(.horizontal, LC.spacingMD)
        .padding(.vertical, LC.spacingSM)
        .background(LC.surface)
    }

    // MARK: - Save Sheet

    private var saveCodeSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: LC.spacingMD) {
                    Text("FILE DETAILS")
                        .lcLabel()

                    VStack(spacing: LC.spacingSM) {
                        HStack {
                            Text("NAME")
                                .font(LC.label(9))
                                .tracking(1)
                                .foregroundStyle(LC.secondary)
                                .frame(width: 60, alignment: .leading)
                            TextField("filename.swift", text: $saveFilename)
                                .font(LC.body(14))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding(LC.spacingSM)
                        .overlay(
                            RoundedRectangle(cornerRadius: LC.radiusSM)
                                .stroke(LC.border, lineWidth: LC.borderWidth)
                        )

                        HStack {
                            Text("DIR")
                                .font(LC.label(9))
                                .tracking(1)
                                .foregroundStyle(LC.secondary)
                                .frame(width: 60, alignment: .leading)
                            TextField("Project folder", text: $saveProject)
                                .font(LC.body(14))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding(LC.spacingSM)
                        .overlay(
                            RoundedRectangle(cornerRadius: LC.radiusSM)
                                .stroke(LC.border, lineWidth: LC.borderWidth)
                        )
                    }

                    if let block = selectedCodeBlock {
                        Text("PREVIEW")
                            .lcLabel()
                            .padding(.top, LC.spacingSM)

                        Text(block.code)
                            .font(LC.code(11))
                            .foregroundStyle(LC.primary)
                            .lineLimit(10)
                            .padding(LC.spacingSM)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LC.surface)
                            .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                            .overlay(
                                RoundedRectangle(cornerRadius: LC.radiusSM)
                                    .stroke(LC.border, lineWidth: LC.borderWidth)
                            )
                    }
                }
                .padding(LC.spacingMD)

                Spacer()
            }
            .background(LC.surfaceElevated)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SAVE CODE")
                        .font(LC.label(12))
                        .tracking(2)
                        .foregroundStyle(LC.primary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSaveSheet = false }
                        .font(LC.body(14))
                        .foregroundStyle(LC.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let block = selectedCodeBlock {
                            let project = saveProject.isEmpty ? "Default" : saveProject
                            _ = try? viewModel.saveCodeBlock(block, projectName: project, filename: saveFilename)
                        }
                        showSaveSheet = false
                    }
                    .font(LC.body(14))
                    .foregroundStyle(LC.accent)
                    .disabled(saveFilename.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func extensionFor(_ language: String) -> String {
        switch language.lowercased() {
        case "swift": return "swift"
        case "python", "py": return "py"
        case "javascript", "js": return "js"
        case "typescript", "ts": return "ts"
        case "rust", "rs": return "rs"
        case "go": return "go"
        case "java": return "java"
        case "c": return "c"
        case "cpp", "c++": return "cpp"
        case "html": return "html"
        case "css": return "css"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "ruby", "rb": return "rb"
        case "shell", "bash", "sh": return "sh"
        default: return "txt"
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    let onSaveCode: (CodeBlock) -> Void

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            // Role label
            Text(roleLabel)
                .font(LC.label(9))
                .tracking(1.5)
                .foregroundStyle(LC.secondary)
                .padding(.horizontal, 2)

            HStack {
                if message.role == .user { Spacer(minLength: 48) }

                VStack(alignment: .leading, spacing: LC.spacingSM) {
                    if message.role == .assistant {
                        MarkdownCodeView(text: message.content, onSaveCode: onSaveCode)
                    } else if message.role == .system {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(LC.accent)
                            Text(message.content)
                                .font(LC.caption(11))
                                .foregroundStyle(LC.secondary)
                        }
                    } else {
                        Text(message.content)
                            .font(LC.body(14))
                            .foregroundStyle(LC.surface)
                    }
                }
                .padding(message.role == .system ? LC.spacingSM : LC.spacingMD - 2)
                .background(backgroundFor(message.role))
                .clipShape(RoundedRectangle(cornerRadius: LC.radiusMD))
                .overlay(
                    RoundedRectangle(cornerRadius: LC.radiusMD)
                        .stroke(borderFor(message.role), lineWidth: LC.borderWidth)
                )

                if message.role == .assistant || message.role == .system { Spacer(minLength: 48) }
            }
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "YOU"
        case .assistant: return "LC"
        case .system: return "SYS"
        }
    }

    private func backgroundFor(_ role: ChatMessage.Role) -> Color {
        switch role {
        case .user: return LC.inverseSurface
        case .assistant: return LC.surfaceElevated
        case .system: return LC.surface
        }
    }

    private func borderFor(_ role: ChatMessage.Role) -> Color {
        switch role {
        case .user: return .clear
        case .assistant: return LC.border
        case .system: return LC.border.opacity(0.5)
        }
    }
}
