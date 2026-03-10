import Combine
import Foundation
import MLXLMCommon
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isGenerating = false
    @Published var error: String?

    /// Set when older messages were dropped to stay within memory limits.
    /// UI can show a subtle indicator that context was trimmed.
    @Published var contextWasTrimmed = false

    /// The file or folder currently focused for context.
    @Published var focusedFile: FileItem?

    /// Tool settings for enabling/disabling tools.
    @Published var toolSettings: [ToolSetting] = [
        ToolSetting(id: "read", name: "read", description: "Read file contents", icon: "doc.text", isEnabled: true),
        ToolSetting(id: "write", name: "write", description: "Create or overwrite files", icon: "square.and.pencil", isEnabled: true),
        ToolSetting(id: "edit", name: "edit", description: "Surgical find-and-replace", icon: "pencil", isEnabled: true),
        ToolSetting(id: "bash", name: "bash", description: "Execute filesystem commands", icon: "terminal", isEnabled: true),
    ]

    /// Returns the set of currently enabled tool names.
    var enabledTools: Set<String> {
        Set(toolSettings.filter { $0.isEnabled }.map { $0.id })
    }

    /// The conversation currently being viewed/edited.
    @Published private(set) var activeConversation: Conversation?

    private let llm = LLMService.shared
    private let fileService = FileService.shared
    private let workingDir = WorkingDirectoryService.shared
    private let gitSync = GitSyncManager.shared
    private let toolExecutor = ToolExecutor()
    private let debugConsole = DebugConsole.shared
    private let store = ConversationStore.shared
    private var generationTask: Task<Void, Never>?

    /// Maximum number of tool-use loop iterations to prevent runaway generation.
    /// On iOS we use fewer rounds to reduce cumulative memory pressure from
    /// tool feedback being added to the context.
    /// Note: First 2-3 rounds may be spent nudging the model to use tools.
    #if os(iOS)
    private let maxToolRounds = 5
    #else
    private let maxToolRounds = 7
    #endif

    /// Debounce timer for auto-saving.
    private var saveTask: Task<Void, Never>?

    /// Key for persisting the active conversation ID.
    private let activeConversationKey = "active_conversation_id"

    /// Cancellables for Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        observeAppLifecycle()
        observeModelChanges()
        restoreLastActiveConversation()
    }

    /// Observe app lifecycle to auto-save before backgrounding.
    private func observeAppLifecycle() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveConversationNow()
                self?.debugConsole.log(
                    "Auto-saved conversation on app resign active",
                    category: .chat, level: .debug
                )
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveConversationNow()
                self?.debugConsole.log(
                    "Auto-saved conversation on background",
                    category: .chat, level: .debug
                )
            }
        }
        #endif
    }

    /// Observe model loading to restore chat session with history.
    private func observeModelChanges() {
        // When model finishes loading, restore the session with existing history
        llm.$isModelLoaded
            .dropFirst() // Skip initial value
            .filter { $0 } // Only when model becomes loaded
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.restoreChatSessionWithHistory()
                }
            }
            .store(in: &cancellables)
    }

    /// Restore the last active conversation on app launch.
    private func restoreLastActiveConversation() {
        guard let idString = UserDefaults.standard.string(forKey: activeConversationKey),
              let id = UUID(uuidString: idString) else {
            debugConsole.log("No previous conversation to restore", category: .chat, level: .debug)
            return
        }

        guard let conversation = store.load(id: id) else {
            debugConsole.log(
                "Failed to restore previous conversation",
                category: .chat, level: .debug,
                details: "id=\(idString)"
            )
            return
        }

        activeConversation = conversation
        messages = conversation.messages

        debugConsole.log(
            "Restored previous conversation",
            category: .chat, level: .debug,
            details: "id=\(idString)\ntitle=\(conversation.title)\nmessages=\(conversation.messages.count)"
        )

        // Session restoration happens when model loads (via observeModelChanges)
    }

    // MARK: - Context Injection

    /// Builds a context string describing the user's project for inclusion
    /// in the LLM's system instructions.
    ///
    /// The output is capped at `LLMService.maxContextCharacters` to prevent
    /// the prompt from consuming too much of the model's context window
    /// (and by extension, too much memory for the KV cache).
    private func contextString() -> String? {
        let maxChars = LLMService.maxContextCharacters
        var context = ""

        // Add focused file/folder context first (highest priority)
        if let focused = focusedFile {
            context += focusedFileContext(focused, budget: maxChars / 2)
            context += "\n\n"
        }

        let remainingBudget = maxChars - context.count

        if gitSync.hasActiveRepo {
            let files = gitSync.listFiles(maxDepth: 2)
            if !files.isEmpty {
                let header = "The user's project directory is: \(gitSync.activeRepoName) (git repo)\n\nProject files:\n"
                let listing = truncatedListing(files, budget: remainingBudget - header.count)
                context += header + listing
            }
        } else if workingDir.workingDirectoryURL != nil {
            let files = workingDir.listFiles(maxDepth: 2)
            if !files.isEmpty {
                let header = "The user's project directory is: \(workingDir.workingDirectoryName)\n\nProject files:\n"
                let listing = truncatedListing(files, budget: remainingBudget - header.count)
                context += header + listing
            }
        } else {
            let files = fileService.listFiles()
            let listing = files.map { $0.isDirectory ? "📁 \($0.name)/" : "  \($0.name)" }
                .joined(separator: "\n")
            let header = "The user's project directory is: LocalCoder. All file paths are relative to the LocalCoder directory."
            let result = header + (listing.isEmpty ? "" : "\n\nProject files:\n\(listing)")
            if result.count > remainingBudget {
                context += String(result.prefix(remainingBudget)) + "\n... (truncated)"
            } else {
                context += result
            }
        }

        return context.isEmpty ? nil : context
    }

    /// Builds context for a focused file or folder.
    private func focusedFileContext(_ item: FileItem, budget: Int) -> String {
        var result = "📌 FOCUSED: \(item.name)\n"

        if item.isDirectory {
            result += "Path: \(item.path)\n"
            result += "Type: Directory\n\n"
            // List contents of the focused directory
            let files = fileService.allFiles(at: item.path, maxDepth: 2)
            if !files.isEmpty {
                result += "Contents:\n"
                for file in files.prefix(50) {
                    let icon = file.isDirectory ? "📁" : "📄"
                    let relativePath = file.path.replacingOccurrences(of: item.path + "/", with: "")
                    result += "\(icon) \(relativePath)\n"
                }
                if files.count > 50 {
                    result += "... and \(files.count - 50) more files"
                }
            }
        } else {
            result += "Path: \(item.path)\n"
            result += "Type: File\n\n"
            // Include file contents
            if let content = fileService.readFile(at: item.path) {
                let maxContent = budget - result.count - 50
                if content.count > maxContent && maxContent > 0 {
                    result += "Contents (truncated):\n```\n"
                    result += String(content.prefix(maxContent))
                    result += "\n```\n... (\(content.count) total characters)"
                } else if maxContent > 0 {
                    result += "Contents:\n```\n"
                    result += content
                    result += "\n```"
                }
            } else {
                result += "(Unable to read file contents)"
            }
        }

        return result
    }

    /// Join file paths into a listing, truncating to fit within `budget` characters.
    private func truncatedListing(_ files: [String], budget: Int) -> String {
        guard budget > 0 else { return "(file listing omitted to save memory)" }
        var result = ""
        var count = 0
        for file in files {
            let line = file + "\n"
            if result.count + line.count > budget {
                result += "... (\(files.count - count) more files)"
                break
            }
            result += line
            count += 1
        }
        return result
    }

    // MARK: - Sending Messages

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        error = nil
        inputText = ""
        messages.append(ChatMessage(role: .user, content: text))
        isGenerating = true

        debugConsole.log(
            "User message queued",
            category: .chat,
            details: "characters=\(text.count)\nmessage_count=\(messages.count)"
        )

        generationTask = Task { [weak self] in
            guard let self else { return }
            await self.runGenerationLoop()
            self.generationTask = nil
            self.isGenerating = false
        }
    }

    // MARK: - Generation + Tool-Use Loop

    /// Generates a response, executes tool calls, and if any produce feedback
    /// (read/bash), feeds results back and re-generates. Caps at `maxToolRounds`.
    ///
    /// Uses a persistent `ChatSession` via `LLMService` so the KV cache is
    /// extended incrementally rather than rebuilt from scratch each turn.
    /// This prevents the O(n²) memory growth that caused crashes in long conversations.
    /// Maximum characters for tool feedback sent back to the model in a single round.
    /// On iOS we use a smaller limit to preserve GPU memory for the KV cache.
    #if os(iOS)
    private let maxToolFeedbackCharacters = 4_000
    #else
    private let maxToolFeedbackCharacters = 8_000
    #endif

    private func runGenerationLoop() async {
        var round = 0
        let context = contextString()

        // Proactively check if we need to compact history before starting
        // This prevents memory issues rather than aborting mid-generation
        proactivelyCompactHistoryIfNeeded()

        while round < maxToolRounds {
            round += 1

            // Check memory pressure before each round — if high, skip further tool rounds
            if round > 1, llm.isMemoryPressureHigh() {
                debugConsole.log(
                    "Skipping tool round \(round) due to high memory pressure",
                    category: .tools,
                    level: .warning
                )
                break
            }

            // Before each tool round, check if we need to compact again
            if round > 1 {
                proactivelyCompactHistoryIfNeeded()
            }

            // Determine what message to send to the model
            let content: String
            let role: Chat.Message.Role

            if round == 1 {
                // First round: send the user's message
                guard let userMsg = messages.last(where: { $0.role == .user }),
                      !userMsg.content.isEmpty else {
                    debugConsole.log("No user message to send", category: .chat, level: .error)
                    break
                }
                content = userMsg.content
                role = .user
            } else {
                // Subsequent rounds: send the tool feedback that was just appended
                guard let feedbackMsg = messages.last(where: { $0.role == .system }),
                      !feedbackMsg.content.isEmpty else {
                    debugConsole.log("No tool feedback to send", category: .chat, level: .error)
                    break
                }
                // Truncate large tool feedback to keep memory bounded
                if feedbackMsg.content.count > maxToolFeedbackCharacters {
                    content = String(feedbackMsg.content.prefix(maxToolFeedbackCharacters))
                        + "\n\n... (output truncated to save memory)"
                } else {
                    content = feedbackMsg.content
                }
                role = .user  // Send tool feedback as user role for better compatibility with small models
            }

            // Append a blank assistant message to stream into
            messages.append(ChatMessage(role: .assistant, content: ""))

            do {
                try Task.checkCancellation()

                try await llm.generate(
                    content: content,
                    role: role,
                    context: context
                ) { [weak self] token in
                    guard let self, let lastIndex = self.messages.indices.last else { return }
                    self.messages[lastIndex].content += token
                }

                try Task.checkCancellation()
            } catch is CancellationError {
                debugConsole.log("Generation cancelled", category: .chat, level: .warning)
                return
            } catch LLMError.shapeMismatchNeedsReset {
                // Handle sliding window attention bug gracefully
                debugConsole.log(
                    "Shape mismatch detected - session was reset",
                    category: .chat,
                    level: .error,
                    details: "This model may have sliding window attention issues with long conversations."
                )
                // Clear messages to match the reset session
                messages.removeAll()
                self.error = "Conversation was too long for this model. Chat has been reset. Try a shorter conversation or switch to Qwen or SmolLM models."
                return
            } catch LLMError.memoryPressureTooHigh {
                // Handle critical memory pressure - reset session to free memory
                debugConsole.log(
                    "Critical memory pressure - aborting generation",
                    category: .chat,
                    level: .error
                )
                llm.resetChat()
                self.error = "Memory is critically low. The chat was reset to prevent a crash. Try using a smaller model or shorter conversations."
                return
            } catch {
                debugConsole.log("Generation failed", category: .chat, level: .error,
                                 details: describe(error))
                self.error = error.localizedDescription
                return
            }

            // Parse tool calls from the assistant's response
            guard let lastMessage = messages.last, lastMessage.role == .assistant else { break }
            let toolCalls = ToolCallParser.parse(lastMessage.content)

            guard !toolCalls.isEmpty else {
                // Try to nudge the model to use tools for the first few rounds
                if round < 3 {
                    debugConsole.log(
                        "No tool calls in round \(round) — nudging for tool use",
                        category: .chat, level: .debug
                    )
                    
                    // Progressively stronger nudges
                    let nudgeMessage: String
                    if round == 1 {
                        nudgeMessage = "You must use a tool. Output a <tool_call> tag. Example: <tool_call>{\"name\": \"bash\", \"command\": \"ls\"}</tool_call>"
                    } else {
                        nudgeMessage = "IMPORTANT: You need to include <tool_call>{\"name\": \"...\", ...}</tool_call> in your response. Do not just describe the action - actually call the tool."
                    }
                    
                    messages.append(ChatMessage(
                        role: .system,
                        content: nudgeMessage
                    ))
                    continue  // Go to next round to retry
                }
                debugConsole.log(
                    "No tool calls after \(round) rounds — giving up",
                    category: .chat, level: .warning
                )
                break
            }

            // Filter tool calls by enabled tools
            let enabled = enabledTools
            let filteredCalls = toolCalls.filter { enabled.contains($0.name) }
            let skippedCount = toolCalls.count - filteredCalls.count

            if skippedCount > 0 {
                debugConsole.log(
                    "Skipped \(skippedCount) disabled tool call(s)",
                    category: .tools,
                    level: .warning
                )
            }

            guard !filteredCalls.isEmpty else {
                debugConsole.log(
                    "All tool calls were disabled — done (round \(round))",
                    category: .tools, level: .debug
                )
                break
            }

            debugConsole.log(
                "Executing \(filteredCalls.count) tool call(s) — round \(round)",
                category: .tools
            )

            // Execute all tool calls
            let results = toolExecutor.executeAll(filteredCalls)

            let successes = results.filter(\.success).count
            let failures = results.count - successes
            debugConsole.log(
                "Tool results",
                category: .tools,
                level: failures > 0 ? .warning : .info,
                details: "successes=\(successes) failures=\(failures)"
            )

            // Collect feedback from read/bash to send back to the model
            let feedbackParts = results.filter(\.feedBack).map(\.message)

            if feedbackParts.isEmpty {
                // Only write/edit — no feedback needed, we're done
                break
            }

            // Feed results back as a system message in the local message list
            // (this is sent to the model via the persistent ChatSession on the next round)
            let feedbackMessage = feedbackParts.joined(separator: "\n\n---\n\n")
            messages.append(ChatMessage(role: .system, content: feedbackMessage))

            debugConsole.log(
                "Feeding tool results back to model",
                category: .tools, level: .debug,
                details: "feedback_parts=\(feedbackParts.count) round=\(round)"
            )
        }

        if round >= maxToolRounds {
            debugConsole.log(
                "Hit max tool rounds (\(maxToolRounds))",
                category: .tools, level: .warning
            )
        }

        // Auto-save after generation completes
        scheduleSave()
    }

    // MARK: - Controls

    func stopGenerating() {
        debugConsole.log("Stop requested", category: .chat, level: .warning)
        generationTask?.cancel()
        isGenerating = false
    }

    func clearChat() {
        generationTask?.cancel()
        llm.resetChat()
        debugConsole.log("Chat cleared", category: .chat, level: .debug)
        messages.removeAll()
        error = nil
        activeConversation = nil
        focusedFile = nil
        contextWasTrimmed = false
        UserDefaults.standard.removeObject(forKey: activeConversationKey)
    }

    // MARK: - Proactive Context Management

    /// Check if the conversation history is approaching memory limits and compact if needed.
    /// This is called before each generation to prevent OOM crashes.
    private func proactivelyCompactHistoryIfNeeded() {
        // Convert messages to Chat.Message format for token estimation
        let history: [Chat.Message] = messages.compactMap { msg in
            switch msg.role {
            case .user:
                return Chat.Message(role: .user, content: msg.content)
            case .assistant:
                return Chat.Message(role: .assistant, content: msg.content)
            case .system:
                return Chat.Message(role: .user, content: msg.content)
            }
        }

        let estimatedTokens = llm.estimateTokens(history)

        // If we're within budget, nothing to do
        guard estimatedTokens > llm.historyTokenBudget else { return }

        debugConsole.log(
            "Context approaching limit, compacting history",
            category: .chat,
            level: .info,
            details: "estimated_tokens=\(estimatedTokens)\nbudget=\(llm.historyTokenBudget)\nmessages=\(messages.count)"
        )

        // Compact the history
        let (compacted, wasCompacted) = llm.compactHistory(history)

        if wasCompacted {
            // Reset the LLM session and restore with compacted history
            llm.resetChat()

            // Update local messages to match compacted history
            // Keep only messages that correspond to the compacted history
            let compactedCount = compacted.count
            if compactedCount < messages.count {
                let dropCount = messages.count - compactedCount
                messages = Array(messages.dropFirst(dropCount))

                debugConsole.log(
                    "Dropped \(dropCount) older messages to fit memory budget",
                    category: .chat,
                    level: .info
                )
            }

            // Restore session with compacted history
            let context = contextString()
            llm.restoreSession(with: compacted, context: context)

            // Notify UI that context was trimmed
            contextWasTrimmed = true
        }
    }

    /// Dismiss the context trimmed notification.
    func dismissContextTrimmedNotice() {
        contextWasTrimmed = false
    }

    // MARK: - File Focus

    /// Sets the focused file or folder for context.
    func setFocus(_ item: FileItem) {
        focusedFile = item
        debugConsole.log(
            "Focused on \(item.isDirectory ? "folder" : "file")",
            category: .chat,
            details: "name=\(item.name)\npath=\(item.path)"
        )
    }

    /// Clears the current file focus.
    func clearFocus() {
        if let focused = focusedFile {
            debugConsole.log("Cleared focus", category: .chat, details: "was=\(focused.name)")
        }
        focusedFile = nil
    }

    /// Returns all available files for the mention picker.
    func availableFilesForMention() -> [FileItem] {
        if gitSync.hasActiveRepo, let repoURL = gitSync.activeRepoURL {
            return fileService.allFiles(at: repoURL.path, maxDepth: 4)
        } else if let workingURL = workingDir.workingDirectoryURL {
            return fileService.allFiles(at: workingURL.path, maxDepth: 4)
        } else {
            return fileService.allFiles(maxDepth: 4)
        }
    }

    // MARK: - Conversation Persistence

    /// Start a brand new conversation (clears current chat).
    func newConversation() {
        // Save current conversation before switching
        saveConversationNow()

        generationTask?.cancel()
        llm.resetChat()
        messages.removeAll()
        error = nil
        activeConversation = nil
        contextWasTrimmed = false

        debugConsole.log("New conversation started", category: .chat, level: .debug)
    }

    /// Load a previously saved conversation by ID.
    func loadConversation(id: UUID) {
        // Save current conversation before switching
        saveConversationNow()

        guard let conversation = store.load(id: id) else {
            debugConsole.log("Failed to load conversation", category: .chat, level: .error,
                             details: "id=\(id.uuidString)")
            return
        }

        generationTask?.cancel()
        llm.resetChat()

        activeConversation = conversation
        messages = conversation.messages
        error = nil

        // Restore the chat session with history so the model has context
        restoreChatSessionWithHistory()

        debugConsole.log(
            "Loaded conversation",
            category: .chat, level: .debug,
            details: "id=\(id.uuidString)\ntitle=\(conversation.title)\nmessages=\(conversation.messages.count)"
        )
    }

    /// Restore the LLM chat session with current message history.
    /// Call this after loading a conversation or when the model changes.
    func restoreChatSessionWithHistory() {
        guard !messages.isEmpty, llm.isModelLoaded else { return }

        // On iOS, limit the history we restore to prevent memory spikes.
        // The most recent messages are most relevant for context anyway.
        #if os(iOS)
        let maxHistoryMessages = 10
        #else
        let maxHistoryMessages = 50
        #endif

        let messagesToRestore = messages.suffix(maxHistoryMessages)

        // Convert ChatMessage array to Chat.Message array for the LLM
        let history: [Chat.Message] = messagesToRestore.compactMap { msg in
            switch msg.role {
            case .user:
                return Chat.Message(role: .user, content: msg.content)
            case .assistant:
                // Truncate long assistant messages to prevent huge KV cache
                let truncatedContent: String
                #if os(iOS)
                if msg.content.count > 2000 {
                    truncatedContent = String(msg.content.prefix(2000)) + "..."
                } else {
                    truncatedContent = msg.content
                }
                #else
                truncatedContent = msg.content
                #endif
                return Chat.Message(role: .assistant, content: truncatedContent)
            case .system:
                // System messages (tool feedback) are sent as user role for compatibility
                // Truncate these as they can be very long (file contents, etc.)
                let truncatedContent: String
                #if os(iOS)
                if msg.content.count > 1000 {
                    truncatedContent = String(msg.content.prefix(1000)) + "...(truncated)"
                } else {
                    truncatedContent = msg.content
                }
                #else
                truncatedContent = msg.content
                #endif
                return Chat.Message(role: .user, content: truncatedContent)
            }
        }

        let context = contextString()
        llm.restoreSession(with: history, context: context)

        debugConsole.log(
            "Restored chat session with history",
            category: .chat, level: .debug,
            details: "messages=\(history.count) (from \(messages.count) total)"
        )
    }

    /// Delete a conversation by ID.
    func deleteConversation(id: UUID) {
        // If deleting the active conversation, clear the chat
        if activeConversation?.id == id {
            clearChat()
        }
        store.delete(id: id)
        debugConsole.log("Deleted conversation", category: .chat, level: .debug,
                         details: "id=\(id.uuidString)")
    }

    /// Schedule an auto-save after a short debounce.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveConversationNow()
        }
    }

    /// Immediately persist the current conversation to disk.
    private func saveConversationNow() {
        // Only save if there are messages worth saving
        guard !messages.isEmpty else {
            // Clear the active conversation ID if no messages
            UserDefaults.standard.removeObject(forKey: activeConversationKey)
            return
        }

        if var conversation = activeConversation {
            conversation.messages = messages
            conversation.updatedAt = Date()
            conversation.deriveTitle()
            activeConversation = conversation
            store.save(conversation)
        } else {
            // First save for a new conversation
            var conversation = Conversation(messages: messages)
            conversation.deriveTitle()
            activeConversation = conversation
            store.save(conversation)
        }

        // Persist the active conversation ID for restoration
        if let id = activeConversation?.id {
            UserDefaults.standard.set(id.uuidString, forKey: activeConversationKey)
        }
    }

    // MARK: - Legacy code block extraction

    func extractCodeBlocks() -> [CodeBlock] {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return [] }
        return parseCodeBlocks(from: lastAssistant.content)
    }

    func saveCodeBlock(_ block: CodeBlock, projectName: String, filename: String) throws -> String {
        try fileService.saveCodeToProject(code: block.code, filename: filename, projectName: projectName)
    }

    private func parseCodeBlocks(from text: String) -> [CodeBlock] {
        var blocks: [CodeBlock] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = text as NSString
        let results = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

        for result in results {
            let langRange = result.range(at: 1)
            let codeRange = result.range(at: 2)
            let language = langRange.location != NSNotFound ? nsString.substring(with: langRange) : ""
            let code = codeRange.location != NSNotFound
                ? nsString.substring(with: codeRange).trimmingCharacters(in: .newlines) : ""

            var filename: String?
            if let first = code.components(separatedBy: "\n").first {
                if first.hasPrefix("// ") && first.contains(".") {
                    filename = first.replacingOccurrences(of: "// ", with: "").trimmingCharacters(in: .whitespaces)
                } else if first.hasPrefix("# ") && first.contains(".") {
                    filename = first.replacingOccurrences(of: "# ", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
            if !code.isEmpty {
                blocks.append(CodeBlock(language: language, code: code, filename: filename))
            }
        }
        return blocks
    }

    private func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "type=\(String(reflecting: type(of: error)))\ndescription=\(error.localizedDescription)\ndomain=\(nsError.domain)\ncode=\(nsError.code)"
    }
}
