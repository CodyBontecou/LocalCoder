import Foundation
import Jinja
import MLX
import MLXLLM
import MLXLMCommon

/// Manages an on-device MLX language model for code generation.
@MainActor
final class LLMService: ObservableObject {
    @Published var isModelLoaded = false
    @Published var isGenerating = false
    @Published var loadingProgress: String = ""
    @Published var activeModelName: String?
    @Published var lastErrorMessage: String?

    private var modelContainer: ModelContainer?
    private var currentModel: ModelInfo?
    private var chatSession: ChatSession?
    private var sessionTurnCount: Int = 0
    private let debugConsole = DebugConsole.shared

    /// Maximum number of turns before resetting the session to reclaim memory.
    /// Each user message + assistant response counts as roughly 2 turns.
    private let maxSessionTurns = 40

    private let lastModelKey = "last_loaded_model_id"

    static let shared = LLMService()

    private init() {
        applyDefaultMemoryTuning(logEvent: false)
        debugConsole.log("LLM service initialized", category: .llm, level: .debug)
    }

    // MARK: - Model Loading

    func loadModel(_ model: ModelInfo) async throws {
        let resolvedModelURL = resolvedLocalModelURL(for: model)
        let sourceDescription = resolvedModelURL?.path ?? model.repositoryID ?? "unknown"

        debugConsole.log(
            "Loading model",
            category: .model,
            details: "name=\(model.name)\nsize=\(model.size)\nsource=\(sourceDescription)"
        )

        unloadModel(logEvent: false)
        lastErrorMessage = nil
        loadingProgress = "Loading \(model.name)..."
        applyDefaultMemoryTuning()

        if let resolvedModelURL {
            debugConsole.log(
                "Model load preflight",
                category: .model,
                level: .debug,
                details: runtimeDiagnostics(modelURL: resolvedModelURL)
            )
        }

        do {
            try preflightLoadCheck(for: model, modelURL: resolvedModelURL)

            let configuration = try configuration(for: model, resolvedModelURL: resolvedModelURL)
            let startSnapshot = Memory.snapshot()

            let container = try await LLMModelFactory.shared.loadContainer(
                hub: ModelManager.shared.hub,
                configuration: configuration,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        let percent = Int(progress.fractionCompleted * 100)
                        self?.loadingProgress = percent > 0
                            ? "Loading \(model.name)... \(percent)%"
                            : "Loading \(model.name)..."
                    }
                }
            )

            modelContainer = container
            currentModel = model
            activeModelName = model.name
            isModelLoaded = true
            loadingProgress = "Loaded \(model.name)"
            lastErrorMessage = nil

            UserDefaults.standard.set(model.id, forKey: lastModelKey)

            let endSnapshot = Memory.snapshot()
            debugConsole.log(
                "Model loaded",
                category: .model,
                details: "name=\(model.name)\n\n\(memoryDeltaReport(from: startSnapshot, to: endSnapshot))"
            )
        } catch {
            loadingProgress = "Failed to load \(model.name)"
            lastErrorMessage = userVisibleDescription(for: error)
            Memory.clearCache()
            debugConsole.log(
                "Model load failed",
                category: .model,
                level: .error,
                details: "\(describe(error))\n\n\(runtimeDiagnostics(modelURL: resolvedModelURL))"
            )
            throw error
        }
    }

    func unloadModel(logEvent: Bool = true) {
        let previousModelName = currentModel?.name

        modelContainer = nil
        currentModel = nil
        chatSession = nil
        sessionTurnCount = 0
        activeModelName = nil
        isModelLoaded = false
        isGenerating = false
        loadingProgress = ""
        lastErrorMessage = nil

        Memory.clearCache()

        if logEvent, let previousModelName {
            debugConsole.log(
                "Model unloaded",
                category: .model,
                details: "name=\(previousModelName)\n\n\(memorySnapshotReport(Memory.snapshot()))"
            )
        }
    }

    func isActive(_ model: ModelInfo) -> Bool {
        currentModel?.id == model.id
    }

    /// Automatically loads the last used model on app launch.
    func autoLoadLastModel() async {
        guard !isModelLoaded else { return }
        guard let lastModelId = UserDefaults.standard.string(forKey: lastModelKey) else {
            debugConsole.log("No previous model to auto-load", category: .model, level: .debug)
            return
        }

        let models = ModelManager.shared.availableModels
        guard let model = models.first(where: { $0.id == lastModelId && $0.isDownloaded }) else {
            debugConsole.log(
                "Last model not available for auto-load",
                category: .model,
                level: .debug,
                details: "id=\(lastModelId)"
            )
            return
        }

        debugConsole.log(
            "Auto-loading last model",
            category: .model,
            details: "name=\(model.name)"
        )

        do {
            try await loadModel(model)
        } catch {
            debugConsole.log(
                "Auto-load failed",
                category: .model,
                level: .error,
                details: "name=\(model.name)\nerror=\(error.localizedDescription)"
            )
        }
    }

    // MARK: - Text Generation

    /// Generate a response to a single message using a persistent chat session.
    ///
    /// The `ChatSession` is reused across calls so the KV cache grows incrementally
    /// instead of being rebuilt from scratch every time. This prevents the O(n²)
    /// memory growth that previously caused crashes in long conversations.
    ///
    /// - Parameters:
    ///   - content: The message text to send.
    ///   - role: The role of the message (`.user` or `.system` for tool feedback).
    ///   - context: Optional dynamic context (e.g. file listings) to include in system instructions.
    ///   - onToken: Callback invoked for each generated token.
    func generate(
        content: String,
        role: Chat.Message.Role = .user,
        context: String? = nil,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let modelContainer else {
            debugConsole.log("Generate requested without a loaded model", category: .llm, level: .error)
            throw LLMError.modelNotLoaded
        }
        guard !content.isEmpty else {
            debugConsole.log("Generate requested with empty content", category: .llm, level: .error)
            throw LLMError.invalidConversation
        }

        isGenerating = true
        let startedAt = Date()
        defer { isGenerating = false }

        // Reset session if turn limit exceeded to bound memory growth
        if sessionTurnCount >= maxSessionTurns {
            debugConsole.log(
                "Session turn limit reached, resetting to reclaim memory",
                category: .llm,
                level: .warning,
                details: "turns=\(sessionTurnCount)\nlimit=\(maxSessionTurns)"
            )
            resetChat()
        }

        // Build instructions: static system prompt + optional dynamic context
        let instructions: String
        if let context, !context.isEmpty {
            instructions = Self.systemPrompt + "\n\n" + context
        } else {
            instructions = Self.systemPrompt
        }

        // Create session on first use, reuse on subsequent calls
        if chatSession == nil {
            var parameters = GenerateParameters()
            parameters.maxTokens = 4096
            parameters.temperature = 0.3
            parameters.topP = 0.9

            chatSession = ChatSession(
                modelContainer,
                instructions: instructions,
                generateParameters: parameters
            )
            debugConsole.log(
                "Created new chat session",
                category: .llm,
                level: .debug
            )
        } else {
            // Update instructions with latest context each turn
            chatSession?.instructions = instructions
        }

        guard let session = chatSession else {
            throw LLMError.modelNotLoaded
        }

        sessionTurnCount += 1

        let activeModelDescription = currentModel?.name ?? "unknown"
        debugConsole.log(
            "Generation started",
            category: .llm,
            details: "model=\(activeModelDescription)\nrole=\(role.rawValue)\ncontent_characters=\(content.count)\nsession_turns=\(sessionTurnCount)"
        )

        var chunkCount = 0
        var characterCount = 0

        do {
            try Task.checkCancellation()

            for try await chunk in session.streamResponse(to: content, role: role, images: [], videos: []) {
                try Task.checkCancellation()

                chunkCount += 1
                characterCount += chunk.count

                if chunkCount == 1 {
                    debugConsole.log(
                        "First response chunk received",
                        category: .llm,
                        level: .debug,
                        details: "elapsed=\(elapsedString(since: startedAt))"
                    )
                } else if chunkCount.isMultiple(of: 50) {
                    debugConsole.log(
                        "Generation still streaming",
                        category: .llm,
                        level: .debug,
                        details: "elapsed=\(elapsedString(since: startedAt))\nchunks=\(chunkCount)\ncharacters=\(characterCount)"
                    )
                }

                onToken(chunk)
            }

            debugConsole.log(
                "Generation finished",
                category: .llm,
                details: "elapsed=\(elapsedString(since: startedAt))\nchunks=\(chunkCount)\ncharacters=\(characterCount)\nsession_turns=\(sessionTurnCount)"
            )

            // Free temporary MLX allocations after each generation
            Memory.clearCache()
        } catch is CancellationError {
            Memory.clearCache()
            debugConsole.log(
                "Generation cancelled",
                category: .llm,
                level: .warning,
                details: "elapsed=\(elapsedString(since: startedAt))\nchunks=\(chunkCount)\ncharacters=\(characterCount)"
            )
            throw CancellationError()
        } catch {
            Memory.clearCache()
            debugConsole.log(
                "Generation failed",
                category: .llm,
                level: .error,
                details: "elapsed=\(elapsedString(since: startedAt))\nchunks=\(chunkCount)\ncharacters=\(characterCount)\n\n\(describe(error))"
            )
            throw error
        }
    }

    /// Reset the chat session, clearing the KV cache and freeing GPU memory.
    /// Call this when the user clears the chat or when memory needs to be reclaimed.
    func resetChat() {
        chatSession = nil
        sessionTurnCount = 0
        Memory.clearCache()
        debugConsole.log(
            "Chat session reset",
            category: .llm,
            level: .debug,
            details: memorySnapshotReport(Memory.snapshot())
        )
    }

    // MARK: - Helpers

    /// The system prompt that instructs the LLM how to use tools.
    static let systemPrompt = """
    You are an expert coding assistant. You have four tools: read, write, edit, and bash.

    Wrap each tool call in <tool_call> tags with a JSON object inside.

    Tools:
    - read: Read a file. {"name": "read", "path": "<FILE>"}
    - write: Create/overwrite a file. {"name": "write", "path": "<FILE>", "content": "<FULL FILE CONTENT>"}
    - edit: Find and replace text in a file. {"name": "edit", "path": "<FILE>", "oldText": "<EXACT TEXT>", "newText": "<REPLACEMENT>"}
    - bash: Run a command. {"name": "bash", "command": "<COMMAND>"}
      Available commands: ls, cat, find, mkdir, rm, cp, mv, wc, head, tail, grep, echo, pwd

    IMPORTANT: Replace <FILE> with the actual filename the user wants. \
    The "path" must match what the user asked for. \
    For write, "content" must contain the ENTIRE file — never leave it empty.

    Rules:
    - Always set "path" to the filename the user requested — never hardcode a path.
    - Escape newlines as \\n and quotes as \\" inside JSON strings.
    - All paths are relative to the project root.
    - You can emit multiple tool calls in one response.
    """

    private func configuration(for model: ModelInfo, resolvedModelURL: URL?) throws -> ModelConfiguration {
        if let resolvedModelURL {
            return ModelConfiguration(directory: resolvedModelURL)
        } else if let repositoryID = model.repositoryID {
            return LLMModelFactory.shared.configuration(id: repositoryID)
        } else {
            throw LLMError.invalidModelConfiguration
        }
    }

    private func resolvedLocalModelURL(for model: ModelInfo) -> URL? {
        if let url = ModelManager.shared.localURL(for: model) {
            return url
        }

        if let localPath = model.localPath {
            return URL(fileURLWithPath: localPath)
        }

        return nil
    }

    private func preflightLoadCheck(for model: ModelInfo, modelURL: URL?) throws {
        guard let modelURL else { return }

        let weightsBytes = modelWeightBytes(at: modelURL)
        guard weightsBytes > 0 else { return }

        let estimatedRequiredBytes = estimateLoadFootprintBytes(weightsBytes: weightsBytes)
        let safeBudgetBytes = safeModelLoadBudgetBytes()

        guard safeBudgetBytes != .max else { return }

        if estimatedRequiredBytes > safeBudgetBytes {
            throw LLMError.modelTooLargeForDevice(
                modelName: model.name,
                requiredBytes: estimatedRequiredBytes,
                budgetBytes: safeBudgetBytes
            )
        }
    }

    private func applyDefaultMemoryTuning(logEvent: Bool = true) {
        #if os(iOS)
        let cacheLimit = 32 * 1024 * 1024
        #else
        let cacheLimit = 128 * 1024 * 1024
        #endif

        let previousValue = Memory.cacheLimit
        guard previousValue != cacheLimit else { return }

        Memory.cacheLimit = cacheLimit

        if logEvent {
            debugConsole.log(
                "Updated MLX cache limit",
                category: .model,
                level: .debug,
                details: "previous=\(formatByteCount(Int64(previousValue)))\ncurrent=\(formatByteCount(Int64(cacheLimit)))"
            )
        }
    }

    private func safeModelLoadBudgetBytes() -> Int64 {
        let deviceInfo = GPU.deviceInfo()
        let recommendedWorkingSet = Int64(clamping: deviceInfo.maxRecommendedWorkingSetSize)
        let physicalMemory = Int64(deviceInfo.memorySize)

        let referenceBudget: Int64
        if recommendedWorkingSet > 0 {
            referenceBudget = recommendedWorkingSet
        } else if physicalMemory > 0 {
            referenceBudget = physicalMemory / 2
        } else {
            return .max
        }

        #if os(iOS)
        return Int64(Double(referenceBudget) * 0.72)
        #else
        return Int64(Double(referenceBudget) * 0.85)
        #endif
    }

    private func estimateLoadFootprintBytes(weightsBytes: Int64) -> Int64 {
        let cacheBytes = Int64(Memory.cacheLimit)
        let activationHeadroom = max(Int64(512 * 1024 * 1024), Int64(Double(weightsBytes) * 0.25))
        return weightsBytes + activationHeadroom + cacheBytes
    }

    private func modelWeightBytes(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent.hasSuffix(".safetensors") {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }

        return totalSize
    }

    private func runtimeDiagnostics(modelURL: URL?) -> String {
        let deviceInfo = GPU.deviceInfo()
        let snapshot = Memory.snapshot()
        let recommendedWorkingSet = Int64(clamping: deviceInfo.maxRecommendedWorkingSetSize)
        let recommendedWorkingSetDescription = recommendedWorkingSet > 0
            ? formatByteCount(recommendedWorkingSet)
            : "unknown"

        var lines = [
            "device_architecture=\(deviceInfo.architecture)",
            "physical_memory=\(formatByteCount(Int64(deviceInfo.memorySize)))",
            "recommended_working_set=\(recommendedWorkingSetDescription)",
            "mlx_memory_limit=\(formatByteCount(Int64(Memory.memoryLimit)))",
            "mlx_cache_limit=\(formatByteCount(Int64(Memory.cacheLimit)))",
            "mlx_snapshot:\n\(snapshot.description)"
        ]

        if let modelURL {
            let weightsBytes = modelWeightBytes(at: modelURL)
            lines.append("model_path=\(modelURL.path)")
            if weightsBytes > 0 {
                lines.append("model_weights=\(formatByteCount(weightsBytes))")
                lines.append("estimated_load=\(formatByteCount(estimateLoadFootprintBytes(weightsBytes: weightsBytes)))")
                let budget = safeModelLoadBudgetBytes()
                if budget != .max {
                    lines.append("safe_budget=\(formatByteCount(budget))")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func memoryDeltaReport(from start: Memory.Snapshot, to end: Memory.Snapshot) -> String {
        let delta = start.delta(end)
        return [
            "start:\n\(start.description)",
            "end:\n\(end.description)",
            "delta:\n\(delta.description)"
        ].joined(separator: "\n\n")
    }

    private func memorySnapshotReport(_ snapshot: Memory.Snapshot) -> String {
        [
            "mlx_cache_limit=\(formatByteCount(Int64(Memory.cacheLimit)))",
            "snapshot:\n\(snapshot.description)"
        ].joined(separator: "\n")
    }

    private func elapsedString(since date: Date) -> String {
        String(format: "%.2fs", Date().timeIntervalSince(date))
    }

    private func userVisibleDescription(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func describe(_ error: Error) -> String {
        // Surface the actual message from Jinja TemplateException (raise_exception).
        // The message property is internal, so use Mirror to extract it.
        if error is TemplateException {
            let mirror = Mirror(reflecting: error)
            let message = mirror.children.first(where: { $0.label == "message" })?.value as? String
            return "type=Jinja.TemplateException\nmessage=\(message ?? "(no message)")"
        }

        // Surface typed Jinja errors (lexer, parser, runtime, syntax)
        if let jinjaError = error as? JinjaError {
            return "type=JinjaError\ndescription=\(jinjaError.localizedDescription)"
        }

        let nsError = error as NSError
        var summary = "type=\(String(reflecting: type(of: error)))\ndescription=\(error.localizedDescription)\ndomain=\(nsError.domain)\ncode=\(nsError.code)"

        if !nsError.userInfo.isEmpty {
            let details = nsError.userInfo
                .map { key, value in "\(key)=\(value)" }
                .sorted()
                .joined(separator: "\n")
            summary += "\nuserInfo:\n\(details)"
        }

        return summary
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case invalidModelConfiguration
    case modelNotLoaded
    case invalidConversation
    case modelTooLargeForDevice(modelName: String, requiredBytes: Int64, budgetBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidModelConfiguration:
            return "The selected model is missing its repository or local path."
        case .modelNotLoaded:
            return "No model is loaded. Please load a model first."
        case .invalidConversation:
            return "There is no valid user prompt to send to the model."
        case let .modelTooLargeForDevice(modelName, requiredBytes, budgetBytes):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "\(modelName) is likely too large for this device. It needs about \(formatter.string(fromByteCount: requiredBytes)) to load safely, but this device budget is only about \(formatter.string(fromByteCount: budgetBytes)). Try a smaller 4-bit model in the 0.5B–3B range."
        }
    }
}
