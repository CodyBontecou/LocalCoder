import Foundation
import MLXLMCommon
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isGenerating = false
    @Published var error: String?

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
    private let maxToolRounds = 5

    /// Debounce timer for auto-saving.
    private var saveTask: Task<Void, Never>?

    // MARK: - Context Injection

    /// Builds a context string describing the user's project for inclusion
    /// in the LLM's system instructions.
    ///
    /// The output is capped at `LLMService.maxContextCharacters` to prevent
    /// the prompt from consuming too much of the model's context window
    /// (and by extension, too much memory for the KV cache).
    private func contextString() -> String? {
        let maxChars = LLMService.maxContextCharacters

        if gitSync.hasActiveRepo {
            let files = gitSync.listFiles(maxDepth: 2)
            if !files.isEmpty {
                let header = "The user's project directory is: \(gitSync.activeRepoName) (git repo)\n\nProject files:\n"
                let listing = truncatedListing(files, budget: maxChars - header.count)
                return header + listing
            }
        } else if workingDir.workingDirectoryURL != nil {
            let files = workingDir.listFiles(maxDepth: 2)
            if !files.isEmpty {
                let header = "The user's project directory is: \(workingDir.workingDirectoryName)\n\nProject files:\n"
                let listing = truncatedListing(files, budget: maxChars - header.count)
                return header + listing
            }
        } else {
            let files = fileService.listFiles()
            let listing = files.map { $0.isDirectory ? "📁 \($0.name)/" : "  \($0.name)" }
                .joined(separator: "\n")
            let header = "The user's project directory is: LocalCoder. All file paths are relative to the LocalCoder directory."
            let result = header + (listing.isEmpty ? "" : "\n\nProject files:\n\(listing)")
            if result.count > maxChars {
                return String(result.prefix(maxChars)) + "\n... (truncated)"
            }
            return result
        }

        return nil
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
    private let maxToolFeedbackCharacters = 8_000

    private func runGenerationLoop() async {
        var round = 0
        let context = contextString()

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
                debugConsole.log(
                    "No tool calls — done (round \(round))",
                    category: .chat, level: .debug
                )
                break
            }

            debugConsole.log(
                "Executing \(toolCalls.count) tool call(s) — round \(round)",
                category: .tools
            )

            // Execute all tool calls
            let results = toolExecutor.executeAll(toolCalls)

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

        debugConsole.log(
            "Loaded conversation",
            category: .chat, level: .debug,
            details: "id=\(id.uuidString)\ntitle=\(conversation.title)\nmessages=\(conversation.messages.count)"
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
        guard !messages.isEmpty else { return }

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
