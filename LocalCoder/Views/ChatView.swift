import SwiftUI

struct ChatView: View {
    @EnvironmentObject var llmService: LLMService
    @StateObject private var viewModel = ChatViewModel()
    @State private var showSaveSheet = false
    @State private var selectedCodeBlock: CodeBlock?
    @State private var saveFilename = ""
    @State private var saveProject = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Model status bar
                modelStatusBar

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message, onSaveCode: { block in
                                    selectedCodeBlock = block
                                    saveFilename = block.filename ?? "code.\(extensionFor(block.language))"
                                    showSaveSheet = true
                                })
                                .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.last?.content) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Error banner
                if let error = viewModel.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error)
                            .font(.caption)
                        Spacer()
                        Button("Dismiss") { viewModel.error = nil }
                            .font(.caption.bold())
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.15))
                    .foregroundStyle(.red)
                }

                // Input bar
                inputBar
            }
            .navigationTitle("LocalCoder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { viewModel.clearChat() }) {
                        Image(systemName: "trash")
                    }
                    .disabled(viewModel.messages.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: ModelManagerView()) {
                        Image(systemName: "cpu")
                    }
                }
            }
            .sheet(isPresented: $showSaveSheet) {
                saveCodeSheet
            }
        }
    }

    // MARK: - Subviews

    private var modelStatusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(llmService.isModelLoaded ? .green : .red)
                .frame(width: 8, height: 8)

            Text(llmService.isModelLoaded ? "Model Ready" : "No Model Loaded")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if viewModel.isGenerating {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Generating...")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask for code...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                Image(systemName: viewModel.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(viewModel.isGenerating ? .red : .green)
            }
            .disabled(!viewModel.isGenerating && (viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !llmService.isModelLoaded))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var saveCodeSheet: some View {
        NavigationStack {
            Form {
                Section("File Details") {
                    TextField("Filename", text: $saveFilename)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Project folder", text: $saveProject)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let block = selectedCodeBlock {
                    Section("Preview") {
                        Text(block.code)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(10)
                    }
                }
            }
            .navigationTitle("Save Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSaveSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let block = selectedCodeBlock {
                            let project = saveProject.isEmpty ? "Default" : saveProject
                            _ = try? viewModel.saveCodeBlock(block, projectName: project, filename: saveFilename)
                        }
                        showSaveSheet = false
                    }
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
            HStack {
                if message.role == .user { Spacer(minLength: 40) }

                VStack(alignment: .leading, spacing: 8) {
                    if message.role == .assistant {
                        MarkdownCodeView(text: message.content, onSaveCode: onSaveCode)
                    } else {
                        Text(message.content)
                            .foregroundStyle(.white)
                    }
                }
                .padding(12)
                .background(message.role == .user ? Color.green.opacity(0.8) : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if message.role == .assistant { Spacer(minLength: 40) }
            }
        }
    }
}
