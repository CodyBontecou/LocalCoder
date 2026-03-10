import Foundation

/// Executes tool calls parsed from LLM output.
///
/// Supports four tools:
///   - **read**:  Read a file's contents (returns content to feed back to model)
///   - **write**: Create or overwrite a file with full content
///   - **edit**:  Surgical find-and-replace within a file (oldText → newText)
///   - **bash**:  Execute common filesystem commands (ls, cat, find, mkdir, rm, etc.)
///
/// All file paths are relative to Documents/LocalCoder/.
final class ToolExecutor {
    private let fileService: FileService

    init(fileService: FileService = .shared) {
        self.fileService = fileService
    }

    /// Execute a single tool call. Returns a ToolResult.
    func execute(_ call: ToolCall) -> ToolResult {
        do {
            switch call.name {
            case "read":
                return try executeRead(call)
            case "write":
                return try executeWrite(call)
            case "edit":
                return try executeEdit(call)
            case "bash":
                return try executeBash(call)
            default:
                return ToolResult(
                    toolCall: call, success: false,
                    message: "Unknown tool: \(call.name)", feedBack: false
                )
            }
        } catch {
            return ToolResult(
                toolCall: call, success: false,
                message: "❌ \(call.name) failed: \(error.localizedDescription)",
                feedBack: call.name == "read" || call.name == "bash"
            )
        }
    }

    /// Execute all tool calls, collecting results.
    func executeAll(_ calls: [ToolCall]) -> [ToolResult] {
        calls.map { execute($0) }
    }

    // MARK: - read

    private func executeRead(_ call: ToolCall) throws -> ToolResult {
        guard let path = call.path else {
            throw ToolError.missingParam("read", "path")
        }
        let fullPath = resolve(path)
        guard let content = fileService.readFile(at: fullPath) else {
            throw ToolError.fileNotFound(path)
        }
        // Truncate very large files to keep context (and KV cache memory) manageable.
        // On iOS, smaller is better — every extra token grows the KV cache in GPU memory.
        // We use a conservative 3K limit on iOS to leave room for multiple file reads
        // without overwhelming the KV cache.
        #if os(iOS)
        let maxChars = 3_000
        #else
        let maxChars = 12_000
        #endif
        let truncated = content.count > maxChars
        let output = truncated
            ? String(content.prefix(maxChars)) + "\n\n... (truncated, \(content.count) total characters)"
            : content
        return ToolResult(
            toolCall: call, success: true,
            message: "Contents of \(path):\n\(output)",
            feedBack: true
        )
    }

    // MARK: - write

    private func executeWrite(_ call: ToolCall) throws -> ToolResult {
        guard let path = call.path else {
            throw ToolError.missingParam("write", "path")
        }
        guard let content = call.content else {
            throw ToolError.missingParam("write", "content")
        }
        let fullPath = resolve(path)
        try fileService.writeFile(content: content, to: fullPath)
        return ToolResult(
            toolCall: call, success: true,
            message: "✅ Wrote \(path) (\(content.count) chars)",
            feedBack: false
        )
    }

    // MARK: - edit

    private func executeEdit(_ call: ToolCall) throws -> ToolResult {
        guard let path = call.path else {
            throw ToolError.missingParam("edit", "path")
        }
        guard let oldText = call.oldText else {
            throw ToolError.missingParam("edit", "oldText")
        }
        guard let newText = call.newText else {
            throw ToolError.missingParam("edit", "newText")
        }

        let fullPath = resolve(path)
        guard let existing = fileService.readFile(at: fullPath) else {
            throw ToolError.fileNotFound(path)
        }

        guard existing.contains(oldText) else {
            throw ToolError.editNoMatch(path, oldText)
        }

        let updated = existing.replacingOccurrences(of: oldText, with: newText)
        try fileService.writeFile(content: updated, to: fullPath)

        return ToolResult(
            toolCall: call, success: true,
            message: "✅ Edited \(path)",
            feedBack: false
        )
    }

    // MARK: - bash (sandboxed filesystem commands)

    private func executeBash(_ call: ToolCall) throws -> ToolResult {
        guard let command = call.command else {
            throw ToolError.missingParam("bash", "command")
        }

        let output = try runSandboxedCommand(command)
        return ToolResult(
            toolCall: call, success: true,
            message: output,
            feedBack: true
        )
    }

    /// Parses and executes a limited set of filesystem commands within the sandbox.
    private func runSandboxedCommand(_ command: String) throws -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = shellSplit(trimmed)
        guard let cmd = parts.first else {
            throw ToolError.emptyCommand
        }

        switch cmd {
        case "ls":
            return try cmdLs(Array(parts.dropFirst()))
        case "cat":
            return try cmdCat(Array(parts.dropFirst()))
        case "find":
            return try cmdFind(Array(parts.dropFirst()))
        case "mkdir":
            return try cmdMkdir(Array(parts.dropFirst()))
        case "rm":
            return try cmdRm(Array(parts.dropFirst()))
        case "cp":
            return try cmdCp(Array(parts.dropFirst()))
        case "mv":
            return try cmdMv(Array(parts.dropFirst()))
        case "wc":
            return try cmdWc(Array(parts.dropFirst()))
        case "head":
            return try cmdHead(Array(parts.dropFirst()))
        case "tail":
            return try cmdTail(Array(parts.dropFirst()))
        case "echo":
            return parts.dropFirst().joined(separator: " ")
        case "pwd":
            return fileService.projectsRoot.path
        case "grep":
            return try cmdGrep(Array(parts.dropFirst()))
        default:
            throw ToolError.unsupportedCommand(cmd)
        }
    }

    // MARK: - Command Implementations

    private func cmdLs(_ args: [String]) throws -> String {
        let path = args.first.flatMap { resolve($0) } ?? fileService.projectsRoot.path
        let url = URL(fileURLWithPath: path)
        let showAll = args.contains("-a") || args.contains("-la") || args.contains("-al")
        let showLong = args.contains("-l") || args.contains("-la") || args.contains("-al")
        let options: FileManager.DirectoryEnumerationOptions = showAll ? [] : [.skipsHiddenFiles]

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: options
        ) else {
            throw ToolError.fileNotFound(args.first ?? ".")
        }

        let sorted = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if showLong {
            return sorted.map { item in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let size = (try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let type = isDir ? "d" : "-"
                return String(format: "%@ %8d  %@", type, size, item.lastPathComponent + (isDir ? "/" : ""))
            }.joined(separator: "\n")
        } else {
            return sorted.map { item in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return item.lastPathComponent + (isDir ? "/" : "")
            }.joined(separator: "\n")
        }
    }

    private func cmdCat(_ args: [String]) throws -> String {
        guard let path = args.first else { throw ToolError.missingParam("cat", "file") }
        let fullPath = resolve(path)
        guard let content = fileService.readFile(at: fullPath) else {
            throw ToolError.fileNotFound(path)
        }
        return content
    }

    private func cmdFind(_ args: [String]) throws -> String {
        let dir = args.first.flatMap { $0.hasPrefix("-") ? nil : $0 } ?? "."
        let baseURL = URL(fileURLWithPath: resolve(dir))

        // Parse -name pattern
        var namePattern: String?
        if let nameIdx = args.firstIndex(of: "-name"), nameIdx + 1 < args.count {
            namePattern = args[nameIdx + 1].replacingOccurrences(of: "*", with: "")
        }

        guard let enumerator = FileManager.default.enumerator(
            at: baseURL, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            throw ToolError.fileNotFound(dir)
        }

        var results: [String] = []
        let basePath = baseURL.path
        for case let url as URL in enumerator {
            let relative = url.path.replacingOccurrences(of: basePath + "/", with: "")
            if let pattern = namePattern {
                if url.lastPathComponent.contains(pattern) {
                    results.append(relative)
                }
            } else {
                results.append(relative)
            }
            if results.count >= 200 { break }
        }
        return results.joined(separator: "\n")
    }

    private func cmdMkdir(_ args: [String]) throws -> String {
        let filtered = args.filter { $0 != "-p" }
        guard let path = filtered.first else { throw ToolError.missingParam("mkdir", "directory") }
        let fullPath = resolve(path)
        try FileManager.default.createDirectory(
            atPath: fullPath, withIntermediateDirectories: true
        )
        return "Created \(path)"
    }

    private func cmdRm(_ args: [String]) throws -> String {
        let filtered = args.filter { $0 != "-r" && $0 != "-rf" && $0 != "-f" }
        guard let path = filtered.first else { throw ToolError.missingParam("rm", "file") }
        let fullPath = resolve(path)
        try FileManager.default.removeItem(atPath: fullPath)
        return "Removed \(path)"
    }

    private func cmdCp(_ args: [String]) throws -> String {
        let filtered = args.filter { $0 != "-r" }
        guard filtered.count >= 2 else { throw ToolError.missingParam("cp", "source destination") }
        let src = resolve(filtered[0])
        let dst = resolve(filtered[1])
        try FileManager.default.copyItem(atPath: src, toPath: dst)
        return "Copied \(filtered[0]) → \(filtered[1])"
    }

    private func cmdMv(_ args: [String]) throws -> String {
        guard args.count >= 2 else { throw ToolError.missingParam("mv", "source destination") }
        let src = resolve(args[0])
        let dst = resolve(args[1])
        try FileManager.default.moveItem(atPath: src, toPath: dst)
        return "Moved \(args[0]) → \(args[1])"
    }

    private func cmdWc(_ args: [String]) throws -> String {
        let filtered = args.filter { !$0.hasPrefix("-") }
        guard let path = filtered.first else { throw ToolError.missingParam("wc", "file") }
        let fullPath = resolve(path)
        guard let content = fileService.readFile(at: fullPath) else {
            throw ToolError.fileNotFound(path)
        }
        let lines = content.components(separatedBy: "\n").count
        let words = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let chars = content.count
        return "\(lines) \(words) \(chars) \(path)"
    }

    private func cmdHead(_ args: [String]) throws -> String {
        var n = 10
        var filePath: String?
        var i = 0
        while i < args.count {
            if args[i] == "-n", i + 1 < args.count, let count = Int(args[i + 1]) {
                n = count; i += 2
            } else if !args[i].hasPrefix("-") {
                filePath = args[i]; i += 1
            } else { i += 1 }
        }
        guard let path = filePath else { throw ToolError.missingParam("head", "file") }
        let fullPath = resolve(path)
        guard let content = fileService.readFile(at: fullPath) else {
            throw ToolError.fileNotFound(path)
        }
        let lines = content.components(separatedBy: "\n")
        return lines.prefix(n).joined(separator: "\n")
    }

    private func cmdTail(_ args: [String]) throws -> String {
        var n = 10
        var filePath: String?
        var i = 0
        while i < args.count {
            if args[i] == "-n", i + 1 < args.count, let count = Int(args[i + 1]) {
                n = count; i += 2
            } else if !args[i].hasPrefix("-") {
                filePath = args[i]; i += 1
            } else { i += 1 }
        }
        guard let path = filePath else { throw ToolError.missingParam("tail", "file") }
        let fullPath = resolve(path)
        guard let content = fileService.readFile(at: fullPath) else {
            throw ToolError.fileNotFound(path)
        }
        let lines = content.components(separatedBy: "\n")
        return lines.suffix(n).joined(separator: "\n")
    }

    private func cmdGrep(_ args: [String]) throws -> String {
        // Simple grep: grep <pattern> <file>
        let filtered = args.filter { !$0.hasPrefix("-") }
        guard filtered.count >= 2 else { throw ToolError.missingParam("grep", "pattern file") }
        let pattern = filtered[0]
        let path = filtered[1]
        let fullPath = resolve(path)
        guard let content = fileService.readFile(at: fullPath) else {
            throw ToolError.fileNotFound(path)
        }
        let lines = content.components(separatedBy: "\n")
        let showLineNumbers = args.contains("-n")
        let matching = lines.enumerated().compactMap { (idx, line) -> String? in
            guard line.localizedCaseInsensitiveContains(pattern) else { return nil }
            return showLineNumbers ? "\(idx + 1):\(line)" : line
        }
        return matching.isEmpty ? "(no matches)" : matching.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func resolve(_ relativePath: String) -> String {
        let sanitized = relativePath.components(separatedBy: "/")
            .filter { !$0.isEmpty && $0 != ".." && $0 != "." }
            .joined(separator: "/")
        return fileService.projectsRoot.appendingPathComponent(sanitized).path
    }

    /// Naive shell-style splitting (respects double quotes).
    private func shellSplit(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for ch in input {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == " " && !inQuotes {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

// MARK: - Errors

enum ToolError: LocalizedError {
    case missingParam(String, String)
    case fileNotFound(String)
    case editNoMatch(String, String)
    case emptyCommand
    case unsupportedCommand(String)

    var errorDescription: String? {
        switch self {
        case .missingParam(let tool, let param):
            return "\(tool) requires \"\(param)\""
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .editNoMatch(let path, let text):
            let preview = text.prefix(80)
            return "edit: oldText not found in \(path): \"\(preview)…\""
        case .emptyCommand:
            return "bash: empty command"
        case .unsupportedCommand(let cmd):
            return "bash: unsupported command \"\(cmd)\". Available: ls, cat, find, mkdir, rm, cp, mv, wc, head, tail, grep, echo, pwd"
        }
    }
}
