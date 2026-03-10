import Foundation

/// Manages project files in the app's Documents directory
final class FileService: ObservableObject {
    static let shared = FileService()

    var projectsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalCoder")
    }

    private init() {
        try? FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    }

    // MARK: - Directory Operations

    func listFiles(at path: String? = nil) -> [FileItem] {
        let url = path.map { URL(fileURLWithPath: $0) } ?? projectsRoot
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return FileItem(
                name: url.lastPathComponent,
                path: url.path,
                isDirectory: isDir,
                children: isDir ? [] : nil
            )
        }.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    func createDirectory(named name: String, at parentPath: String? = nil) throws {
        let parent = parentPath.map { URL(fileURLWithPath: $0) } ?? projectsRoot
        let dirURL = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    }

    // MARK: - File Operations

    func readFile(at path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    func writeFile(content: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func saveCodeToProject(code: String, filename: String, projectName: String) throws -> String {
        let projectDir = projectsRoot.appendingPathComponent(projectName)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let filePath = projectDir.appendingPathComponent(filename).path
        try writeFile(content: code, to: filePath)
        return filePath
    }

    func deleteItem(at path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    func renameItem(at path: String, to newName: String) throws {
        let url = URL(fileURLWithPath: path)
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        try FileManager.default.moveItem(at: url, to: newURL)
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func isDirectory(at path: String) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    // MARK: - Project Helpers

    func listProjects() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: projectsRoot.path))?.filter {
            isDirectory(at: projectsRoot.appendingPathComponent($0).path)
        }.sorted() ?? []
    }

    // MARK: - Recursive File Listing

    /// Returns all files and folders recursively up to maxDepth.
    /// Results are returned as FileItems with paths relative to the base.
    func allFiles(at basePath: String? = nil, maxDepth: Int = 4) -> [FileItem] {
        let baseURL = basePath.map { URL(fileURLWithPath: $0) } ?? projectsRoot
        var results: [FileItem] = []
        enumerateFiles(at: baseURL, relativeTo: baseURL, depth: 0, maxDepth: maxDepth, results: &results)
        return results.sorted { a, b in
            // Directories first, then alphabetical
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func enumerateFiles(
        at url: URL,
        relativeTo base: URL,
        depth: Int,
        maxDepth: Int,
        results: inout [FileItem]
    ) {
        guard depth <= maxDepth else { return }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let relativePath = item.path.replacingOccurrences(of: base.path + "/", with: "")

            let fileItem = FileItem(
                name: item.lastPathComponent,
                path: item.path,
                isDirectory: isDir,
                children: isDir ? [] : nil
            )
            results.append(fileItem)

            if isDir {
                enumerateFiles(at: item, relativeTo: base, depth: depth + 1, maxDepth: maxDepth, results: &results)
            }
        }
    }
}
