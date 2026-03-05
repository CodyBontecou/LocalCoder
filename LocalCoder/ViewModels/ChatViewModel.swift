import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isGenerating = false
    @Published var error: String?

    private let llm = LLMService.shared
    private let fileService = FileService.shared

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, content: text))
        messages.append(ChatMessage(role: .assistant, content: ""))
        isGenerating = true

        Task {
            do {
                try await llm.generate(messages: Array(messages.dropLast())) { [weak self] token in
                    guard let self else { return }
                    if let lastIndex = self.messages.indices.last {
                        self.messages[lastIndex].content += token
                    }
                }
            } catch {
                self.error = error.localizedDescription
            }
            isGenerating = false
        }
    }

    func stopGenerating() {
        isGenerating = false
    }

    func clearChat() {
        messages.removeAll()
        error = nil
    }

    /// Extract code blocks from the last assistant message
    func extractCodeBlocks() -> [CodeBlock] {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return [] }
        return parseCodeBlocks(from: lastAssistant.content)
    }

    func saveCodeBlock(_ block: CodeBlock, projectName: String, filename: String) throws -> String {
        try fileService.saveCodeToProject(code: block.code, filename: filename, projectName: projectName)
    }

    /// Parse markdown code blocks from text
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
            let code = codeRange.location != NSNotFound ? nsString.substring(with: codeRange).trimmingCharacters(in: .newlines) : ""

            // Try to extract filename from first comment line
            var filename: String?
            let lines = code.components(separatedBy: "\n")
            if let first = lines.first {
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
}
