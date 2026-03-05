import Foundation

/// Git operations via GitHub REST API
/// Supports: clone, commit, push, pull, status, branch management
final class GitService: ObservableObject {
    static let shared = GitService()

    @Published var output: [String] = []

    private var token: String {
        UserDefaults.standard.string(forKey: "github_token") ?? ""
    }

    private var username: String {
        UserDefaults.standard.string(forKey: "github_username") ?? ""
    }

    private let fileService = FileService.shared

    private init() {}

    // MARK: - Local Git State (stored as JSON metadata)

    private struct RepoMeta: Codable {
        var owner: String
        var repo: String
        var branch: String
        var lastSHA: String?
        var trackedFiles: [String: String] // path -> sha
    }

    private func metaPath(for projectPath: String) -> String {
        URL(fileURLWithPath: projectPath).appendingPathComponent(".localcoder_git.json").path
    }

    private func loadMeta(for projectPath: String) -> RepoMeta? {
        guard let data = FileManager.default.contents(atPath: metaPath(for: projectPath)),
              let meta = try? JSONDecoder().decode(RepoMeta.self, from: data) else { return nil }
        return meta
    }

    private func saveMeta(_ meta: RepoMeta, for projectPath: String) {
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: URL(fileURLWithPath: metaPath(for: projectPath)))
        }
    }

    // MARK: - API Helpers

    private func apiRequest(endpoint: String, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        guard !token.isEmpty else { throw GitError.noToken }

        var url = endpoint.hasPrefix("http") ? endpoint : "https://api.github.com\(endpoint)"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitError.networkError
        }
        return (data, httpResponse)
    }

    // MARK: - Clone

    func clone(owner: String, repo: String, branch: String = "main", to projectPath: String) async throws {
        log("Cloning \(owner)/\(repo) (\(branch))...")

        // Get the tree
        let (data, resp) = try await apiRequest(endpoint: "/repos/\(owner)/\(repo)/git/trees/\(branch)?recursive=1")
        guard resp.statusCode == 200 else { throw GitError.apiFailed("Clone failed: HTTP \(resp.statusCode)") }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = json["sha"] as? String,
              let tree = json["tree"] as? [[String: Any]] else {
            throw GitError.parseFailed
        }

        var trackedFiles: [String: String] = [:]
        let baseURL = URL(fileURLWithPath: projectPath)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        for item in tree {
            guard let path = item["path"] as? String,
                  let type = item["type"] as? String else { continue }

            if type == "tree" {
                try FileManager.default.createDirectory(
                    at: baseURL.appendingPathComponent(path),
                    withIntermediateDirectories: true
                )
            } else if type == "blob", let blobSHA = item["sha"] as? String {
                log("  Downloading \(path)...")
                let (blobData, _) = try await apiRequest(
                    endpoint: "/repos/\(owner)/\(repo)/git/blobs/\(blobSHA)"
                )

                if let blobJSON = try JSONSerialization.jsonObject(with: blobData) as? [String: Any],
                   let content = blobJSON["content"] as? String,
                   let encoding = blobJSON["encoding"] as? String, encoding == "base64" {
                    let cleaned = content.replacingOccurrences(of: "\n", with: "")
                    if let decoded = Data(base64Encoded: cleaned) {
                        let filePath = baseURL.appendingPathComponent(path)
                        try FileManager.default.createDirectory(
                            at: filePath.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try decoded.write(to: filePath)
                        trackedFiles[path] = blobSHA
                    }
                }
            }
        }

        let meta = RepoMeta(owner: owner, repo: repo, branch: branch, lastSHA: sha, trackedFiles: trackedFiles)
        saveMeta(meta, for: projectPath)
        log("✅ Cloned \(tree.filter { ($0["type"] as? String) == "blob" }.count) files")
    }

    // MARK: - Commit & Push

    func commitAndPush(projectPath: String, message: String) async throws {
        guard var meta = loadMeta(for: projectPath) else {
            throw GitError.notARepo
        }

        log("Preparing commit: \(message)")

        let baseURL = URL(fileURLWithPath: projectPath)
        var blobs: [(path: String, sha: String)] = []

        // Walk all files in project (excluding metadata)
        let files = collectFiles(at: baseURL)
        for file in files {
            let relativePath = file.path.replacingOccurrences(of: projectPath + "/", with: "")
            if relativePath.hasPrefix(".localcoder_git") { continue }

            let content = try Data(contentsOf: file)
            let base64 = content.base64EncodedString()

            log("  Creating blob for \(relativePath)...")
            let (blobData, blobResp) = try await apiRequest(
                endpoint: "/repos/\(meta.owner)/\(meta.repo)/git/blobs",
                method: "POST",
                body: ["content": base64, "encoding": "base64"]
            )

            guard blobResp.statusCode == 201,
                  let blobJSON = try JSONSerialization.jsonObject(with: blobData) as? [String: Any],
                  let sha = blobJSON["sha"] as? String else {
                throw GitError.apiFailed("Failed to create blob for \(relativePath)")
            }

            blobs.append((path: relativePath, sha: sha))
        }

        // Create tree
        let treeItems: [[String: Any]] = blobs.map { blob in
            ["path": blob.path, "mode": "100644", "type": "blob", "sha": blob.sha]
        }

        log("Creating tree...")
        let (treeData, treeResp) = try await apiRequest(
            endpoint: "/repos/\(meta.owner)/\(meta.repo)/git/trees",
            method: "POST",
            body: ["tree": treeItems]
        )

        guard treeResp.statusCode == 201,
              let treeJSON = try JSONSerialization.jsonObject(with: treeData) as? [String: Any],
              let treeSHA = treeJSON["sha"] as? String else {
            throw GitError.apiFailed("Failed to create tree")
        }

        // Get current HEAD
        let (refData, _) = try await apiRequest(
            endpoint: "/repos/\(meta.owner)/\(meta.repo)/git/ref/heads/\(meta.branch)"
        )
        guard let refJSON = try JSONSerialization.jsonObject(with: refData) as? [String: Any],
              let obj = refJSON["object"] as? [String: Any],
              let parentSHA = obj["sha"] as? String else {
            throw GitError.apiFailed("Failed to get HEAD ref")
        }

        // Create commit
        log("Creating commit...")
        let (commitData, commitResp) = try await apiRequest(
            endpoint: "/repos/\(meta.owner)/\(meta.repo)/git/commits",
            method: "POST",
            body: [
                "message": message,
                "tree": treeSHA,
                "parents": [parentSHA]
            ]
        )

        guard commitResp.statusCode == 201,
              let commitJSON = try JSONSerialization.jsonObject(with: commitData) as? [String: Any],
              let commitSHA = commitJSON["sha"] as? String else {
            throw GitError.apiFailed("Failed to create commit")
        }

        // Update ref (push)
        log("Pushing...")
        let (_, pushResp) = try await apiRequest(
            endpoint: "/repos/\(meta.owner)/\(meta.repo)/git/refs/heads/\(meta.branch)",
            method: "PATCH",
            body: ["sha": commitSHA, "force": false]
        )

        guard pushResp.statusCode == 200 else {
            throw GitError.apiFailed("Push failed: HTTP \(pushResp.statusCode)")
        }

        meta.lastSHA = commitSHA
        saveMeta(meta, for: projectPath)
        log("✅ Pushed commit \(String(commitSHA.prefix(7))) to \(meta.branch)")
    }

    // MARK: - Pull

    func pull(projectPath: String) async throws {
        guard let meta = loadMeta(for: projectPath) else {
            throw GitError.notARepo
        }

        log("Pulling latest from \(meta.owner)/\(meta.repo)...")
        try await clone(owner: meta.owner, repo: meta.repo, branch: meta.branch, to: projectPath)
    }

    // MARK: - Create Repo

    func createRepo(name: String, description: String = "", isPrivate: Bool = false) async throws {
        log("Creating repository \(name)...")

        let (data, resp) = try await apiRequest(
            endpoint: "/user/repos",
            method: "POST",
            body: [
                "name": name,
                "description": description,
                "private": isPrivate,
                "auto_init": true
            ]
        )

        guard resp.statusCode == 201 else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                throw GitError.apiFailed("Create repo failed: \(message)")
            }
            throw GitError.apiFailed("Create repo failed: HTTP \(resp.statusCode)")
        }

        log("✅ Created repository \(name)")
    }

    // MARK: - Init (link local project to repo)

    func initRepo(projectPath: String, owner: String, repo: String, branch: String = "main") {
        let meta = RepoMeta(owner: owner, repo: repo, branch: branch, lastSHA: nil, trackedFiles: [:])
        saveMeta(meta, for: projectPath)
        log("✅ Initialized git tracking for \(owner)/\(repo)")
    }

    // MARK: - Status

    func isGitRepo(at projectPath: String) -> Bool {
        loadMeta(for: projectPath) != nil
    }

    func getRepoInfo(at projectPath: String) -> (owner: String, repo: String, branch: String)? {
        guard let meta = loadMeta(for: projectPath) else { return nil }
        return (meta.owner, meta.repo, meta.branch)
    }

    // MARK: - List Repos

    func listRepos() async throws -> [(name: String, fullName: String, isPrivate: Bool)] {
        let (data, resp) = try await apiRequest(endpoint: "/user/repos?sort=updated&per_page=30")
        guard resp.statusCode == 200 else { throw GitError.apiFailed("Failed to list repos") }

        guard let repos = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw GitError.parseFailed
        }

        return repos.compactMap { repo in
            guard let name = repo["name"] as? String,
                  let fullName = repo["full_name"] as? String,
                  let isPrivate = repo["private"] as? Bool else { return nil }
            return (name, fullName, isPrivate)
        }
    }

    // MARK: - Helpers

    private func collectFiles(at url: URL) -> [URL] {
        var files: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return files
        }
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
               values.isRegularFile == true {
                files.append(fileURL)
            }
        }
        return files
    }

    private func log(_ message: String) {
        DispatchQueue.main.async {
            self.output.append(message)
        }
    }

    func clearOutput() {
        output.removeAll()
    }
}

enum GitError: LocalizedError {
    case noToken
    case networkError
    case notARepo
    case apiFailed(String)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .noToken: return "No GitHub token configured. Go to Settings to add your Personal Access Token."
        case .networkError: return "Network request failed"
        case .notARepo: return "This project is not linked to a GitHub repository"
        case .apiFailed(let msg): return msg
        case .parseFailed: return "Failed to parse API response"
        }
    }
}
