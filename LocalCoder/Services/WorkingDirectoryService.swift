import Foundation

/// Manages a user-chosen working directory with security-scoped bookmark persistence.
///
/// On iOS, apps are sandboxed. To let the LLM write files to an arbitrary folder
/// (e.g. iCloud Drive, On My iPhone), the user picks a directory via the system
/// file picker. We store a security-scoped bookmark so access persists across launches.
final class WorkingDirectoryService: ObservableObject {
    static let shared = WorkingDirectoryService()

    @Published var workingDirectoryURL: URL?
    @Published var workingDirectoryName: String = ""

    private let bookmarkKey = "working_directory_bookmark"
    private var accessingSecurityScope = false

    private init() {
        restoreBookmark()
    }

    deinit {
        stopAccessing()
    }

    // MARK: - Directory Selection

    /// Call when the user picks a directory from the file picker
    func setWorkingDirectory(_ url: URL) {
        // Stop accessing previous directory
        stopAccessing()

        // Start accessing the new one
        guard url.startAccessingSecurityScopedResource() else {
            print("⚠️ Failed to access security-scoped resource")
            return
        }
        accessingSecurityScope = true

        // Save bookmark for persistence
        do {
            let bookmark = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        } catch {
            print("⚠️ Failed to create bookmark: \(error)")
        }

        workingDirectoryURL = url
        workingDirectoryName = url.lastPathComponent
    }

    /// Clear the working directory
    func clearWorkingDirectory() {
        stopAccessing()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        workingDirectoryURL = nil
        workingDirectoryName = ""
    }

    // MARK: - File Operations (relative to working directory)

    /// Write a file at a path relative to the working directory
    func writeFile(relativePath: String, content: String) throws {
        guard let base = workingDirectoryURL else {
            throw WorkingDirectoryError.noDirectorySelected
        }

        // Sanitize path — prevent escaping the working directory
        let sanitized = sanitizePath(relativePath)
        let fileURL = base.appendingPathComponent(sanitized)

        // Create intermediate directories
        let dirURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        // Write file
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Read a file at a path relative to the working directory
    func readFile(relativePath: String) -> String? {
        guard let base = workingDirectoryURL else { return nil }
        let sanitized = sanitizePath(relativePath)
        let fileURL = base.appendingPathComponent(sanitized)
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    /// Delete a file at a path relative to the working directory
    func deleteFile(relativePath: String) throws {
        guard let base = workingDirectoryURL else {
            throw WorkingDirectoryError.noDirectorySelected
        }
        let sanitized = sanitizePath(relativePath)
        let fileURL = base.appendingPathComponent(sanitized)
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Check if a file exists relative to working directory
    func fileExists(relativePath: String) -> Bool {
        guard let base = workingDirectoryURL else { return false }
        let sanitized = sanitizePath(relativePath)
        let fileURL = base.appendingPathComponent(sanitized)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// List files in the working directory (for context injection)
    func listFiles(maxDepth: Int = 3) -> [String] {
        guard let base = workingDirectoryURL else { return [] }
        var result: [String] = []
        collectFiles(at: base, relativeTo: base, depth: 0, maxDepth: maxDepth, into: &result)
        return result.sorted()
    }

    // MARK: - Private

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        if isStale {
            // Re-save a fresh bookmark
            if let fresh = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
        }

        guard url.startAccessingSecurityScopedResource() else { return }
        accessingSecurityScope = true
        workingDirectoryURL = url
        workingDirectoryName = url.lastPathComponent
    }

    private func stopAccessing() {
        if accessingSecurityScope {
            workingDirectoryURL?.stopAccessingSecurityScopedResource()
            accessingSecurityScope = false
        }
    }

    /// Remove leading slashes, ".." components, etc. to prevent path traversal
    private func sanitizePath(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
            .filter { !$0.isEmpty && $0 != ".." && $0 != "." }
        return components.joined(separator: "/")
    }

    private func collectFiles(at url: URL, relativeTo base: URL, depth: Int, maxDepth: Int, into result: inout [String]) {
        guard depth < maxDepth else { return }

        let skipDirs: Set<String> = [".git", "node_modules", ".build", "DerivedData", "__pycache__", ".next", "Pods"]

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            let name = item.lastPathComponent
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let relativePath = item.path.replacingOccurrences(of: base.path + "/", with: "")

            if isDir {
                if !skipDirs.contains(name) {
                    result.append(relativePath + "/")
                    collectFiles(at: item, relativeTo: base, depth: depth + 1, maxDepth: maxDepth, into: &result)
                }
            } else {
                result.append(relativePath)
            }
        }
    }
}

// MARK: - Errors

enum WorkingDirectoryError: LocalizedError {
    case noDirectorySelected
    case pathTraversalAttempt

    var errorDescription: String? {
        switch self {
        case .noDirectorySelected:
            return "No working directory selected. Open a folder first."
        case .pathTraversalAttempt:
            return "Invalid file path."
        }
    }
}
