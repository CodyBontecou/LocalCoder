import Foundation

// MARK: - Tool Call Model

/// A single tool invocation parsed from LLM output.
struct ToolCall: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String?
    let content: String?
    let oldText: String?
    let newText: String?
    let command: String?

    static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.id == rhs.id
    }
}

/// Result of executing a single tool call.
struct ToolResult: Identifiable {
    let id = UUID()
    let toolCall: ToolCall
    let success: Bool
    let message: String
    /// True if this result should be fed back to the model (read, bash).
    let feedBack: Bool
}

// MARK: - Parser

/// Parses structured tool calls from LLM output.
///
/// Recognised tools: `read`, `write`, `edit`, `bash`
///
/// Supports multiple formats that local models commonly produce:
/// 1. `<tool_call>{...}</tool_call>` — preferred format
/// 2. ```json code blocks containing tool-call JSON
/// 3. Bare JSON objects with a recognised "name" field
final class ToolCallParser {

    static let toolNames: Set<String> = ["read", "write", "edit", "bash"]

    // MARK: - Public API

    /// Extracts all tool calls from a completed response.
    static func parse(_ text: String) -> [ToolCall] {
        var calls = parseToolCallTags(text)
        if calls.isEmpty {
            calls = parseJSONCodeBlocks(text)
        }
        if calls.isEmpty {
            calls = parseBareJSON(text)
        }
        return calls
    }

    /// Check if text contains any complete tool calls (useful during streaming)
    static func hasToolCalls(_ text: String) -> Bool {
        if text.contains("</tool_call>") { return true }
        for name in toolNames {
            if text.contains("\"\(name)\"") { return true }
        }
        return false
    }

    /// Check if a tool call block is currently being streamed (opened but not closed)
    static func hasOpenToolCall(_ text: String) -> Bool {
        let openCount = text.components(separatedBy: "<tool_call>").count - 1
        let closeCount = text.components(separatedBy: "</tool_call>").count - 1
        if openCount > closeCount { return true }

        if text.components(separatedBy: "```json").count - 1 > 0 {
            let parts = text.components(separatedBy: "```")
            var opens = 0
            var closes = 0
            for (i, part) in parts.enumerated() where i > 0 {
                if part.hasPrefix("json") || part.hasPrefix("JSON") {
                    opens += 1
                } else {
                    closes += 1
                }
            }
            if opens > closes { return true }
        }

        return false
    }

    // MARK: - Strategy 1: <tool_call> tags

    private static func parseToolCallTags(_ text: String) -> [ToolCall] {
        let pattern = #"<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { match -> ToolCall? in
            guard match.numberOfRanges >= 2 else { return nil }
            return parseToolJSON(nsString.substring(with: match.range(at: 1)))
        }
    }

    // MARK: - Strategy 2: ```json code blocks

    private static func parseJSONCodeBlocks(_ text: String) -> [ToolCall] {
        let pattern = #"```(?:json|JSON)\s*\n([\s\S]*?)\n\s*```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { match -> ToolCall? in
            guard match.numberOfRanges >= 2 else { return nil }
            let json = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            return parseToolJSON(json)
        }
    }

    // MARK: - Strategy 3: Bare JSON objects

    private static func parseBareJSON(_ text: String) -> [ToolCall] {
        var calls: [ToolCall] = []
        for name in toolNames {
            let searchToken = "\"\(name)\""
            var searchRange = text.startIndex..<text.endIndex
            while let tokenRange = text.range(of: searchToken, range: searchRange) {
                if let braceStart = findBraceStart(in: text, before: tokenRange.lowerBound),
                   let braceEnd = findBraceEnd(in: text, from: braceStart) {
                    let jsonString = String(text[braceStart...braceEnd])
                    if let call = parseToolJSON(jsonString) {
                        calls.append(call)
                    }
                    searchRange = text.index(after: braceEnd)..<text.endIndex
                } else {
                    searchRange = tokenRange.upperBound..<text.endIndex
                }
            }
        }
        // Deduplicate
        var seen = Set<String>()
        return calls.filter {
            let key = "\($0.name):\($0.path ?? ""):\($0.command ?? "")"
            return seen.insert(key).inserted
        }
    }

    // MARK: - JSON → ToolCall

    private static func parseToolJSON(_ jsonString: String) -> ToolCall? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              toolNames.contains(name) else {
            return nil
        }

        return ToolCall(
            name: name,
            path: json["path"] as? String,
            content: json["content"] as? String,
            oldText: json["oldText"] as? String ?? json["old_text"] as? String,
            newText: json["newText"] as? String ?? json["new_text"] as? String,
            command: json["command"] as? String
        )
    }

    // MARK: - Brace Matching

    private static func findBraceStart(in text: String, before index: String.Index) -> String.Index? {
        var i = index
        while i > text.startIndex {
            i = text.index(before: i)
            if text[i] == "{" { return i }
            if text.distance(from: i, to: index) > 2000 { return nil }
        }
        return nil
    }

    private static func findBraceEnd(in text: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escape = false
        var i = start
        while i < text.endIndex {
            let ch = text[i]
            if escape {
                escape = false
            } else if ch == "\\" && inString {
                escape = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 { return i }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }
}
