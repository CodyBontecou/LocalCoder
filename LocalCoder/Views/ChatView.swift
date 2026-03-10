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
    @State private var showMentionPicker = false
    @State private var mentionFilter = ""
    @State private var availableFiles: [FileItem] = []
    @State private var showSlashCommandPicker = false
    @State private var slashFilter = ""
    @State private var showToolsMenu = false
    @State private var showModelMenu = false
    @StateObject private var modelManager = ModelManager.shared
    @State private var showNoModelAlert = false
    @FocusState private var inputFieldFocused: Bool
    @Binding var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status strip
                statusStrip

                // Working directory
                directoryStrip

                // Messages or Welcome
                if viewModel.messages.isEmpty {
                    WelcomeView()
                } else {
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
                }

                // Context trimmed notice (non-intrusive)
                if viewModel.contextWasTrimmed {
                    HStack(spacing: LC.spacingSM) {
                        Image(systemName: "scissors")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(LC.accent)

                        Text("Older messages trimmed to save memory")
                            .font(LC.caption(11))
                            .foregroundStyle(LC.secondary)

                        Spacer()

                        Button(action: { viewModel.dismissContextTrimmedNotice() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(LC.secondary.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, LC.spacingMD)
                    .padding(.vertical, 6)
                    .background(LC.accent.opacity(0.05))
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
                    DebugPanelView(console: debugConsole, isExpanded: $isDebugPanelExpanded, keyboardVisible: isInputFocused)
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
            .alert("No Model Selected", isPresented: $showNoModelAlert) {
                Button("Select Model") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showModelMenu = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please select a model before chatting. You can download and load a model from the model menu.")
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
        .background(LC.surface)
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
        .background(LC.surface)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Model menu (shown when /model is selected)
            if showModelMenu {
                ModelMenuView(
                    modelManager: modelManager,
                    llmService: llmService,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            showModelMenu = false
                        }
                    }
                )
                .padding(.horizontal, LC.spacingSM)
                .padding(.bottom, LC.spacingXS)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Tools menu (shown when /tools is selected)
            if showToolsMenu {
                ToolsMenuView(
                    tools: $viewModel.toolSettings,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            showToolsMenu = false
                        }
                    }
                )
                .padding(.horizontal, LC.spacingSM)
                .padding(.bottom, LC.spacingXS)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Slash command picker (shown when "/" is typed)
            if showSlashCommandPicker {
                SlashCommandPicker(
                    filter: slashFilter,
                    onSelect: { command in
                        executeSlashCommand(command)
                    },
                    onDismiss: {
                        dismissSlashCommandPicker()
                    }
                )
                .padding(.horizontal, LC.spacingSM)
                .padding(.bottom, LC.spacingXS)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Mention picker (shown above input when "@" is typed)
            if showMentionPicker {
                FileMentionPicker(
                    files: availableFiles,
                    filter: mentionFilter,
                    onSelect: { file in
                        selectMentionedFile(file)
                    },
                    onDismiss: {
                        dismissMentionPicker()
                    }
                )
                .padding(.horizontal, LC.spacingSM)
                .padding(.bottom, LC.spacingXS)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Focused file chip (shown when a file is focused)
            if let focused = viewModel.focusedFile {
                HStack {
                    FocusedFileChip(file: focused) {
                        viewModel.clearFocus()
                    }
                    Spacer()
                }
                .padding(.horizontal, LC.spacingSM)
                .padding(.bottom, LC.spacingXS)
            }

            TerminalInputBar(
                text: $viewModel.inputText,
                isGenerating: viewModel.isGenerating,
                isEnabled: llmService.isModelLoaded,
                inputFieldFocused: $inputFieldFocused,
                isInputFocused: $isInputFocused,
                onSubmit: {
                    // If slash command picker is showing with exactly one match, autocomplete it
                    if showSlashCommandPicker {
                        let filtered = SlashCommand.filtered(by: slashFilter)
                        if filtered.count == 1 {
                            executeSlashCommand(filtered[0])
                            return
                        }
                    }
                    if !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Check if model is loaded before sending
                        if !llmService.isModelLoaded {
                            showNoModelAlert = true
                            return
                        }
                        viewModel.sendMessage()
                    }
                },
                onStop: { viewModel.stopGenerating() },
                onSend: {
                    // Check if model is loaded before sending
                    if !llmService.isModelLoaded {
                        showNoModelAlert = true
                        return
                    }
                    viewModel.sendMessage()
                }
            )
            .onChange(of: viewModel.inputText) { _, newValue in
                handleInputChange(newValue)
            }
        }
    }

    // MARK: - Input Handling

    private func handleInputChange(_ text: String) {
        // Check if we should show the slash command picker
        // Only show if "/" is at the start of the input
        if text.hasPrefix("/") {
            let afterSlash = String(text.dropFirst())
            // Show picker if "/" is at start and no space yet
            if !afterSlash.contains(" ") {
                slashFilter = afterSlash
                if !showSlashCommandPicker {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showSlashCommandPicker = true
                        showMentionPicker = false
                    }
                }
                return
            }
        }

        // Hide slash picker if not applicable
        if showSlashCommandPicker {
            dismissSlashCommandPicker()
        }

        // Check if we should show the mention picker
        if let atIndex = text.lastIndex(of: "@") {
            let afterAt = String(text[text.index(after: atIndex)...])
            // Show picker if "@" is at end or followed by non-space characters
            if afterAt.isEmpty || !afterAt.contains(" ") {
                mentionFilter = afterAt
                if !showMentionPicker {
                    availableFiles = viewModel.availableFilesForMention()
                    withAnimation(.easeOut(duration: 0.15)) {
                        showMentionPicker = true
                    }
                }
                return
            }
        }

        // Hide picker if no active mention
        if showMentionPicker {
            dismissMentionPicker()
        }
    }

    // MARK: - Slash Command Handling

    private func executeSlashCommand(_ command: SlashCommand) {
        viewModel.inputText = ""
        dismissSlashCommandPicker()

        switch command {
        case .new:
            viewModel.newConversation()
        case .tools:
            withAnimation(.easeOut(duration: 0.15)) {
                showToolsMenu = true
            }
        case .model:
            withAnimation(.easeOut(duration: 0.15)) {
                showModelMenu = true
            }
        case .clear:
            viewModel.clearChat()
        case .help:
            showHelpMessage()
        }
    }

    private func showHelpMessage() {
        let helpText = """
        Available commands:
        • /new - Start a new conversation
        • /tools - Toggle tools on/off
        • /model - Select or download a model
        • /clear - Clear chat history
        • /help - Show this help

        Tips:
        • Use @filename to focus on a specific file
        • Focused files are included in the context sent to the model
        """
        viewModel.messages.append(ChatMessage(role: .system, content: helpText))
    }

    private func dismissSlashCommandPicker() {
        withAnimation(.easeOut(duration: 0.1)) {
            showSlashCommandPicker = false
        }
        slashFilter = ""
    }

    // MARK: - Mention Handling

    private func selectMentionedFile(_ file: FileItem) {
        // Remove the "@..." from input and set focus
        if let atIndex = viewModel.inputText.lastIndex(of: "@") {
            viewModel.inputText = String(viewModel.inputText[..<atIndex])
        }
        viewModel.setFocus(file)
        dismissMentionPicker()
    }

    private func dismissMentionPicker() {
        withAnimation(.easeOut(duration: 0.1)) {
            showMentionPicker = false
        }
        mentionFilter = ""
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

// MARK: - Terminal Input Bar

struct TerminalInputBar: View {
    @Binding var text: String
    let isGenerating: Bool
    let isEnabled: Bool
    var inputFieldFocused: FocusState<Bool>.Binding
    @Binding var isInputFocused: Bool
    let onSubmit: () -> Void
    let onStop: () -> Void
    let onSend: () -> Void
    
    @State private var cursorVisible = true
    
    var body: some View {
        HStack(spacing: LC.spacingSM) {
            // Input field with border
            HStack(spacing: 0) {
                // Blinking cursor when empty and not focused
                if text.isEmpty && !inputFieldFocused.wrappedValue {
                    Text("▌")
                        .font(LC.code(14))
                        .foregroundStyle(LC.secondary.opacity(cursorVisible ? 0.6 : 0))
                        .allowsHitTesting(false)
                }
                
                TextField("", text: $text, axis: .vertical)
                    .font(LC.code(14))
                    .foregroundStyle(LC.primary)
                    .tint(LC.accent)
                    .lineLimit(1...3)
                    .focused(inputFieldFocused)
                    .onSubmit(onSubmit)
                    .opacity(text.isEmpty && !inputFieldFocused.wrappedValue ? 0.01 : 1)
            }
            .padding(.horizontal, LC.spacingSM)
            .padding(.vertical, 6)
            .background(LC.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
            .overlay(
                RoundedRectangle(cornerRadius: LC.radiusSM)
                    .stroke(inputFieldFocused.wrappedValue ? LC.accent : LC.border, lineWidth: LC.borderWidth)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                inputFieldFocused.wrappedValue = true
            }
            
            // Send/Stop button
            if !text.isEmpty || isGenerating {
                Button(action: {
                    if isGenerating {
                        onStop()
                    } else {
                        onSend()
                    }
                }) {
                    Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isGenerating ? .white : LC.surface)
                        .frame(width: 26, height: 26)
                        .background(isGenerating ? LC.destructive : LC.accent)
                        .clipShape(Circle())
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, LC.spacingSM)
        .padding(.vertical, LC.spacingXS)
        .background(LC.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(LC.border).frame(height: LC.borderWidth)
        }
        .onChange(of: isInputFocused) { _, newValue in
            inputFieldFocused.wrappedValue = newValue
        }
        .onChange(of: inputFieldFocused.wrappedValue) { _, newValue in
            isInputFocused = newValue
        }
        .onAppear {
            startCursorBlink()
        }
    }
    
    private var canSend: Bool {
        // Allow tapping send button when there's text, even if model isn't loaded
        // The onSend callback will show an alert if no model is loaded
        isGenerating || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func startCursorBlink() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            cursorVisible.toggle()
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
