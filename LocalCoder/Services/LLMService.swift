import Foundation
import Jinja
import MLX
import MLXLLM
import MLXLMCommon
#if canImport(UIKit)
import UIKit
#endif

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

    /// Estimated token budget for the conversation history (not including the new message).
    /// This is a conservative estimate - actual tokens may vary by model.
    /// On iOS we use a much smaller budget because the KV cache lives in GPU memory.
    #if os(iOS)
    private let maxHistoryTokenBudget = 2_000  // ~8KB of text
    #else
    private let maxHistoryTokenBudget = 8_000  // ~32KB of text
    #endif

    /// Maximum characters allowed for the context string injected into system instructions.
    /// Keeps the prompt from ballooning when the user opens a large repo.
    /// On iOS we use a much smaller limit to preserve memory for the KV cache.
    #if os(iOS)
    static let maxContextCharacters = 2_000
    #else
    static let maxContextCharacters = 4_000
    #endif

    /// Tracks the estimated token count in the current session's history.
    /// This is a rough estimate (chars / 4) but helps us proactively manage context.
    private var estimatedSessionTokens: Int = 0

    private let lastModelKey = "last_loaded_model_id"

    static let shared = LLMService()

    private init() {
        applyDefaultMemoryTuning(logEvent: false)
        observeMemoryWarnings()
        debugConsole.log("LLM service initialized", category: .llm, level: .debug)
    }

    // MARK: - Memory Warning Handling

    private func observeMemoryWarnings() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
        #endif
    }

    /// Respond to iOS memory warnings by aggressively freeing GPU memory.
    /// If we're not mid-generation, reset the chat session entirely (drops the KV cache).
    /// If we are generating, at least clear the MLX allocator cache.
    private func handleMemoryWarning() {
        let snapshot = Memory.snapshot()
        debugConsole.log(
            "Received iOS memory warning",
            category: .app,
            level: .warning,
            details: "is_generating=\(isGenerating)\nsession_turns=\(sessionTurnCount)\n\(memorySnapshotReport(snapshot))"
        )

        if !isGenerating {
            // Safe to nuke the full session — frees the KV cache
            chatSession = nil
            sessionTurnCount = 0
            Memory.clearCache()
            debugConsole.log(
                "Freed chat session in response to memory warning",
                category: .app,
                level: .warning,
                details: memorySnapshotReport(Memory.snapshot())
            )
        } else {
            // Mid-generation: clear what we can without breaking the stream
            Memory.clearCache()
            debugConsole.log(
                "Cleared MLX cache during generation (memory warning)",
                category: .app,
                level: .warning
            )
        }
    }

    /// Returns `true` when memory pressure is high enough that starting a new
    /// generation is risky. Call before kicking off `generate()`.
    func isMemoryPressureHigh() -> Bool {
        let deviceInfo = GPU.deviceInfo()
        let recommendedWorkingSet = Int64(clamping: deviceInfo.maxRecommendedWorkingSetSize)
        guard recommendedWorkingSet > 0 else { return false }

        let snapshot = Memory.snapshot()
        let activeBytes = Int64(clamping: snapshot.activeMemory)

        // If we're already using more than 80% of the recommended working set, bail
        let threshold = Double(recommendedWorkingSet) * 0.80
        let isHigh = Double(activeBytes) > threshold

        if isHigh {
            debugConsole.log(
                "Memory pressure is HIGH",
                category: .app,
                level: .warning,
                details: "active=\(formatByteCount(activeBytes))\nrecommended_limit=\(formatByteCount(recommendedWorkingSet))\nthreshold=80%"
            )
        }
        return isHigh
    }

    /// Returns `true` when memory is critically high and generation should abort.
    /// Uses a higher threshold (90%) than `isMemoryPressureHigh` because this is
    /// called during streaming where aborting mid-generation is disruptive.
    private func isMemoryCritical() -> Bool {
        let deviceInfo = GPU.deviceInfo()
        let recommendedWorkingSet = Int64(clamping: deviceInfo.maxRecommendedWorkingSetSize)
        guard recommendedWorkingSet > 0 else { return false }

        let snapshot = Memory.snapshot()
        let activeBytes = Int64(clamping: snapshot.activeMemory)

        // Critical threshold at 90% — we're about to be jetsammed
        let threshold = Double(recommendedWorkingSet) * 0.90
        return Double(activeBytes) > threshold
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

        // Check if we're approaching the token budget and should reset
        let newContentTokens = estimateTokens(content)
        let projectedTokens = estimatedSessionTokens + newContentTokens + 500  // +500 for expected response

        if projectedTokens > maxHistoryTokenBudget {
            debugConsole.log(
                "Token budget would be exceeded, resetting session",
                category: .llm,
                level: .info,
                details: "current_tokens=\(estimatedSessionTokens)\nnew_content_tokens=\(newContentTokens)\nprojected=\(projectedTokens)\nbudget=\(maxHistoryTokenBudget)"
            )
            resetChat()
        }

        // If memory pressure is high, also reset as a safety measure
        if isMemoryPressureHigh() && estimatedSessionTokens > 0 {
            debugConsole.log(
                "High memory pressure — resetting session before generation",
                category: .llm,
                level: .warning
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

            // Update estimated token count with the new content and response
            let inputTokens = estimateTokens(content)
            let outputTokens = estimateTokens(String(repeating: "x", count: characterCount))
            estimatedSessionTokens += inputTokens + outputTokens

            debugConsole.log(
                "Generation finished",
                category: .llm,
                details: "elapsed=\(elapsedString(since: startedAt))\nchunks=\(chunkCount)\ncharacters=\(characterCount)\nsession_turns=\(sessionTurnCount)\nestimated_session_tokens=\(estimatedSessionTokens)"
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
            
            // Check for broadcast_shapes error which indicates sliding window attention bug
            let errorDescription = describe(error)
            if errorDescription.contains("broadcast_shapes") || errorDescription.contains("cannot be broadcast") {
                debugConsole.log(
                    "Detected sliding window attention shape mismatch - resetting session",
                    category: .llm,
                    level: .error,
                    details: "This may be caused by a model with sliding window attention (e.g., Gemma 3n). Resetting session to recover.\n\n\(errorDescription)"
                )
                resetChat()
                throw LLMError.shapeMismatchNeedsReset
            }
            
            debugConsole.log(
                "Generation failed",
                category: .llm,
                level: .error,
                details: "elapsed=\(elapsedString(since: startedAt))\nchunks=\(chunkCount)\ncharacters=\(characterCount)\n\n\(errorDescription)"
            )
            throw error
        }
    }

    /// Reset the chat session, clearing the KV cache and freeing GPU memory.
    /// Call this when the user clears the chat or when memory needs to be reclaimed.
    func resetChat() {
        chatSession = nil
        sessionTurnCount = 0
        estimatedSessionTokens = 0
        Memory.clearCache()
        debugConsole.log(
            "Chat session reset",
            category: .llm,
            level: .debug,
            details: memorySnapshotReport(Memory.snapshot())
        )
    }

    // MARK: - Token Budget Management

    /// Estimate the number of tokens in a string.
    /// Uses a rough heuristic of ~4 characters per token (varies by model/language).
    func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Estimate total tokens for an array of messages.
    func estimateTokens(_ messages: [Chat.Message]) -> Int {
        messages.reduce(0) { sum, msg in
            sum + estimateTokens(msg.content)
        }
    }

    /// Returns the maximum token budget for conversation history.
    var historyTokenBudget: Int {
        maxHistoryTokenBudget
    }

    /// Compact a message history to fit within the token budget.
    /// Keeps the most recent messages and drops older ones.
    /// Returns the compacted history and whether any messages were dropped.
    func compactHistory(_ history: [Chat.Message], budget: Int? = nil) -> (messages: [Chat.Message], wasCompacted: Bool) {
        let targetBudget = budget ?? maxHistoryTokenBudget
        var totalTokens = estimateTokens(history)

        guard totalTokens > targetBudget else {
            return (history, false)
        }

        // Keep dropping the oldest messages until we're under budget
        var compacted = history
        while totalTokens > targetBudget && compacted.count > 2 {
            // Always keep at least the last user message and last assistant message
            let removed = compacted.removeFirst()
            totalTokens -= estimateTokens(removed.content)
        }

        debugConsole.log(
            "Compacted history to fit token budget",
            category: .llm,
            level: .info,
            details: "original_messages=\(history.count)\ncompacted_messages=\(compacted.count)\nestimated_tokens=\(totalTokens)\nbudget=\(targetBudget)"
        )

        return (compacted, true)
    }

    /// Check if adding new content would exceed the token budget.
    /// Returns true if compaction is recommended before generation.
    func shouldCompactBeforeGeneration(newContentLength: Int, currentHistoryTokens: Int) -> Bool {
        let newTokens = estimateTokens(String(repeating: "x", count: newContentLength))
        // Leave room for the new message plus expected response (~500 tokens)
        let projectedTotal = currentHistoryTokens + newTokens + 500
        return projectedTotal > maxHistoryTokenBudget
    }

    /// Restore the chat session with a previous conversation history.
    /// This re-hydrates the KV cache so the model has context of past messages.
    ///
    /// - Parameters:
    ///   - history: Array of `Chat.Message` representing the conversation history.
    ///   - context: Optional dynamic context (e.g. file listings) to include in system instructions.
    func restoreSession(with history: [Chat.Message], context: String? = nil) {
        guard let modelContainer else {
            debugConsole.log(
                "Cannot restore session without a loaded model",
                category: .llm,
                level: .error
            )
            return
        }

        // Reset any existing session first
        chatSession = nil
        sessionTurnCount = 0
        estimatedSessionTokens = estimateTokens(history)
        Memory.clearCache()

        // Build instructions with optional context
        let instructions: String
        if let context, !context.isEmpty {
            instructions = Self.systemPrompt + "\n\n" + context
        } else {
            instructions = Self.systemPrompt
        }

        // Create session with history for prompt re-hydration
        var parameters = GenerateParameters()
        parameters.maxTokens = 4096
        parameters.temperature = 0.3
        parameters.topP = 0.9

        chatSession = ChatSession(
            modelContainer,
            instructions: instructions,
            history: history,
            generateParameters: parameters
        )

        // Count existing turns (each user+assistant pair is one turn)
        let userMessageCount = history.filter { $0.role == .user }.count
        sessionTurnCount = userMessageCount

        debugConsole.log(
            "Restored chat session with history",
            category: .llm,
            level: .debug,
            details: "history_messages=\(history.count)\nsession_turns=\(sessionTurnCount)"
        )
    }

    // MARK: - Helpers

    /// The system prompt that instructs the LLM how to use tools.
    static let systemPrompt = """
    You are an expert coding assistant with access to tools. You MUST use tools to complete tasks.

    TOOLS (use these to help the user):
    - read: Read file contents. Usage: <tool_call>{"name": "read", "path": "file.txt"}</tool_call>
    - write: Create/overwrite files. Usage: <tool_call>{"name": "write", "path": "file.txt", "content": "..."}</tool_call>
    - edit: Find and replace text. Usage: <tool_call>{"name": "edit", "path": "file.txt", "oldText": "...", "newText": "..."}</tool_call>
    - bash: Run commands. Usage: <tool_call>{"name": "bash", "command": "ls -la"}</tool_call>

    IMPORTANT RULES:
    1. You MUST include <tool_call>...</tool_call> tags in your response to use a tool
    2. Do NOT just describe what you would do - actually call the tool
    3. Every response should contain at least one tool call when the user asks you to do something
    4. Start tasks by exploring with bash (ls) or read

    EXAMPLE - User says "create a hello world file":
    I'll create a hello world Python file for you.
    <tool_call>{"name": "write", "path": "hello.py", "content": "print('Hello, World!')"}</tool_call>

    EXAMPLE - User says "list files":
    <tool_call>{"name": "bash", "command": "ls -la"}</tool_call>

    EXAMPLE - User says "build a website about cats":
    I'll create an HTML file with a cats website.
    <tool_call>{"name": "write", "path": "index.html", "content": "<!DOCTYPE html>\\n<html>\\n<head><title>Cats</title></head>\\n<body><h1>Welcome to Cats!</h1></body>\\n</html>"}</tool_call>
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
        // Smaller cache on iOS to leave more headroom for the KV cache during generation.
        // The MLX cache holds temporary allocations; we clear it after each generation anyway.
        #if os(iOS)
        let cacheLimit = 16 * 1024 * 1024  // 16 MB
        #else
        let cacheLimit = 128 * 1024 * 1024
        #endif

        let previousCacheLimit = Memory.cacheLimit
        let cacheChanged = previousCacheLimit != cacheLimit

        if cacheChanged {
            Memory.cacheLimit = cacheLimit
        }

        // On iOS, also constrain the overall memory limit to prevent MLX from
        // allocating past what the OS will tolerate before jetsam kills us.
        #if os(iOS)
        let deviceInfo = GPU.deviceInfo()
        let recommendedWorkingSet = Int64(clamping: deviceInfo.maxRecommendedWorkingSetSize)
        if recommendedWorkingSet > 0 {
            // Use 65% of the recommended working set as the hard MLX memory limit.
            // This is conservative but necessary — iOS jetsam is aggressive and will
            // kill us without warning if we exceed limits. The remaining 35% is for:
            // - UIKit and SwiftUI view hierarchy
            // - System frameworks
            // - Transient allocations during token generation
            // - Safety margin for memory spikes
            let memoryLimit = Int(Double(recommendedWorkingSet) * 0.65)
            let previousMemoryLimit = Memory.memoryLimit
            if previousMemoryLimit != memoryLimit {
                Memory.memoryLimit = memoryLimit
                if logEvent {
                    debugConsole.log(
                        "Updated MLX memory limit",
                        category: .model,
                        level: .debug,
                        details: "previous=\(formatByteCount(Int64(previousMemoryLimit)))\ncurrent=\(formatByteCount(Int64(memoryLimit)))\nrecommended_working_set=\(formatByteCount(recommendedWorkingSet))"
                    )
                }
            }
        }
        #endif

        if cacheChanged, logEvent {
            debugConsole.log(
                "Updated MLX cache limit",
                category: .model,
                level: .debug,
                details: "previous=\(formatByteCount(Int64(previousCacheLimit)))\ncurrent=\(formatByteCount(Int64(cacheLimit)))"
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

        // On iOS we need to be very conservative. The model weights are just
        // the starting point — generation requires additional memory for:
        // - KV cache (grows with conversation length)
        // - Activation tensors
        // - MLX cache for temporary allocations
        // Using 55% leaves enough headroom for multi-turn conversations.
        #if os(iOS)
        return Int64(Double(referenceBudget) * 0.55)
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
    case shapeMismatchNeedsReset
    case memoryPressureTooHigh

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
        case .shapeMismatchNeedsReset:
            return "The conversation exceeded this model's context limit. The chat has been reset. Please try a shorter conversation or use a different model."
        case .memoryPressureTooHigh:
            return "Memory is critically low. Generation was stopped to prevent a crash. Try clearing the chat or using a smaller model."
        }
    }
}
