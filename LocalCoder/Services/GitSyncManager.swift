import Foundation

/// Coordinates the local git repo on the device filesystem.
///
/// Files live in Documents/LocalCoder/Repos/<repoName>/ — always writable, no
/// security-scoped bookmarks needed. The AI's write_file tool writes
/// here, and the user can commit+push to GitHub whenever they want.
@MainActor
final class GitSyncManager: ObservableObject {
    static let shared = GitSyncManager()

    @Published var isCloning = false
    @Published var isStaging = false
    @Published var isCommitting = false
    @Published var isPushing = false
    @Published var isPulling = false
    @Published var activeRepoName: String = ""
    @Published var activeRepoBranch: String = ""
    @Published var lastCommitSHA: String = ""
    @Published var statusMessage: String = ""

    /// The root where all cloned repos live: Documents/LocalCoder/Repos/
    var reposRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalCoder", isDirectory: true)
            .appendingPathComponent("Repos", isDirectory: true)
    }

    /// The directory of the currently active repo, or nil if none
    var activeRepoURL: URL? {
        guard !activeRepoName.isEmpty else { return nil }
        return reposRoot.appendingPathComponent(activeRepoName, isDirectory: true)
    }

    /// Whether we have an active local git repo
    var hasActiveRepo: Bool {
        guard let url = activeRepoURL else { return false }
        return FileManager.default.fileExists(
            atPath: url.appendingPathComponent(".git").path
        )
    }

    /// The LocalGitService for the active repo
    var gitService: LocalGitService? {
        guard let url = activeRepoURL else { return nil }
        return LocalGitService(localURL: url)
    }

    /// Non-isolated check for whether a repo is active (safe to call from any context)
    nonisolated var hasActiveRepoSync: Bool {
        let name = UserDefaults.standard.string(forKey: "git_sync_state_repo") ?? ""
        guard !name.isEmpty else { return false }
        let repoURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalCoder", isDirectory: true)
            .appendingPathComponent("Repos", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        return FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent(".git").path
        )
    }

    /// Non-isolated URL for the active repo (safe to call from any context)
    nonisolated var activeRepoURLSync: URL? {
        let name = UserDefaults.standard.string(forKey: "git_sync_state_repo") ?? ""
        guard !name.isEmpty else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalCoder", isDirectory: true)
            .appendingPathComponent("Repos", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    // PAT from Keychain
    var pat: String {
        get { KeychainService.load(key: "github_pat") ?? "" }
        set { KeychainService.save(key: "github_pat", value: newValue) }
    }

    private let stateKey = "git_sync_state"

    private init() {
        try? FileManager.default.createDirectory(at: reposRoot, withIntermediateDirectories: true)
        restoreState()
    }

    // MARK: - Clone

    func cloneRepo(remoteURL: String) async throws {
        isCloning = true
        statusMessage = "Cloning..."
        defer { isCloning = false }

        // Normalize: "owner/repo" → "https://github.com/owner/repo"
        var normalized = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.contains("://") && !normalized.hasPrefix("git@") {
            normalized = "https://github.com/\(normalized)"
        }

        // Extract repo name from URL
        let repoName = extractRepoName(from: normalized)
        let dest = reposRoot.appendingPathComponent(repoName, isDirectory: true)

        // Clean target if it exists
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }

        // Ensure .git suffix
        var cloneURL = normalized
        if !cloneURL.hasSuffix(".git") { cloneURL += ".git" }

        let git = LocalGitService(localURL: dest)
        let result = try await git.clone(remoteURL: cloneURL, pat: pat)

        activeRepoName = repoName
        activeRepoBranch = result.branch
        lastCommitSHA = result.commitSHA
        statusMessage = "Cloned \(result.fileCount) files"
        saveState()
    }

    // MARK: - Create New Local Repo

    /// Creates a new local git repository (git init) without any remote.
    func createLocalRepo(name: String) async throws {
        isCloning = true  // Reuse the cloning state
        statusMessage = "Creating..."
        defer { isCloning = false }

        let dest = reposRoot.appendingPathComponent(name, isDirectory: true)

        // Check if already exists
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            throw NSError(domain: "GitSync", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "A repository named '\(name)' already exists locally."])
        }

        let git = LocalGitService(localURL: dest)
        let sha = try await git.initRepo(initialBranch: "main")

        activeRepoName = name
        activeRepoBranch = "main"
        lastCommitSHA = sha
        statusMessage = "Created local repo"
        saveState()
    }

    // MARK: - Create and Push to GitHub

    /// Creates a new repository on GitHub, sets the remote, and pushes.
    /// Automatically commits any pending changes before pushing.
    func createAndPushToGitHub(repoName: String, description: String = "", isPrivate: Bool = true) async throws {
        guard let git = gitService else { throw LocalGitError.notCloned }

        isPushing = true
        statusMessage = "Creating on GitHub..."
        defer { isPushing = false }

        // 1. Create repo on GitHub
        let result = try await GitHubAuthService.shared.createRepo(
            name: repoName,
            description: description,
            isPrivate: isPrivate
        )

        statusMessage = "Setting remote..."

        // 2. Set the remote
        try await git.setRemote(name: "origin", url: result.cloneURL)

        // 3. Commit any pending changes before pushing
        let authorName = UserDefaults.standard.string(forKey: "git_author_name") ?? "LocalCoder"
        let authorEmail = UserDefaults.standard.string(forKey: "git_author_email") ?? "localcoder@device"
        
        do {
            statusMessage = "Committing changes..."
            let sha = try await git.commit(
                message: "Initial commit from LocalCoder",
                authorName: authorName,
                authorEmail: authorEmail
            )
            lastCommitSHA = sha
        } catch LocalGitError.noChanges {
            // No changes to commit, that's fine - just push existing commits
        }

        statusMessage = "Pushing..."

        // 4. Push to the new remote
        try await git.push(pat: pat)

        statusMessage = "Pushed to \(result.fullName)"
        saveState()
    }

    // MARK: - Check if Remote Exists

    func hasRemote() async -> Bool {
        guard let git = gitService else { return false }
        return (try? await git.getRemoteURL()) != nil
    }

    // MARK: - Pull

    func pull() async throws {
        guard let git = gitService else { throw LocalGitError.notCloned }
        isPulling = true
        statusMessage = "Pulling..."
        defer { isPulling = false }

        let result = try await git.pull(pat: pat)
        lastCommitSHA = result.newCommitSHA
        statusMessage = result.updated ? "Updated to \(String(result.newCommitSHA.prefix(7)))" : "Already up to date"
        saveState()
    }

    // MARK: - Commit & Push

    func commitAndPush(message: String) async throws {
        guard let git = gitService else { throw LocalGitError.notCloned }
        isPushing = true
        statusMessage = "Pushing..."
        defer { isPushing = false }

        // Use stored git identity or defaults
        let authorName = UserDefaults.standard.string(forKey: "git_author_name") ?? "LocalCoder"
        let authorEmail = UserDefaults.standard.string(forKey: "git_author_email") ?? "localcoder@device"

        let result = try await git.commitAndPush(
            message: message,
            authorName: authorName,
            authorEmail: authorEmail,
            pat: pat
        )

        lastCommitSHA = result.commitSHA
        statusMessage = "Pushed \(String(result.commitSHA.prefix(7)))"
        saveState()
    }

    // MARK: - Stage All

    func stageAll() async throws {
        guard let git = gitService else { throw LocalGitError.notCloned }
        isStaging = true
        statusMessage = "Staging..."
        defer { isStaging = false }

        let count = try await git.stageAll()
        statusMessage = "Staged \(count) entries"
    }

    // MARK: - Commit (without push)

    func commitOnly(message: String) async throws {
        guard let git = gitService else { throw LocalGitError.notCloned }
        isCommitting = true
        statusMessage = "Committing..."
        defer { isCommitting = false }

        let authorName = UserDefaults.standard.string(forKey: "git_author_name") ?? "LocalCoder"
        let authorEmail = UserDefaults.standard.string(forKey: "git_author_email") ?? "localcoder@device"

        let sha = try await git.commit(
            message: message,
            authorName: authorName,
            authorEmail: authorEmail
        )

        lastCommitSHA = sha
        statusMessage = "Committed \(String(sha.prefix(7)))"
        saveState()
    }

    // MARK: - Push (without commit)

    func pushOnly() async throws {
        guard let git = gitService else { throw LocalGitError.notCloned }
        isPushing = true
        statusMessage = "Pushing..."
        defer { isPushing = false }

        try await git.push(pat: pat)
        statusMessage = "Pushed to remote"
        saveState()
    }

    // MARK: - Changed Files

    func changedFiles() async -> [ChangedFile] {
        guard let git = gitService, git.hasGitDirectory else { return [] }
        return (try? await git.changedFiles()) ?? []
    }

    // MARK: - File Operations (for the AI's write_file tool)

    func writeFile(relativePath: String, content: String) throws {
        guard let git = gitService else { throw LocalGitError.notCloned }
        try git.writeFile(relativePath: relativePath, content: content)
    }

    func readFile(relativePath: String) -> String? {
        gitService?.readFile(relativePath: relativePath)
    }

    func deleteFile(relativePath: String) throws {
        guard let git = gitService else { throw LocalGitError.notCloned }
        try git.deleteFile(relativePath: relativePath)
    }

    func fileExists(relativePath: String) -> Bool {
        gitService?.fileExists(relativePath: relativePath) ?? false
    }

    // MARK: - Non-isolated file operations (callable from ToolExecutor)

    /// Write a file to the active repo (safe to call from non-MainActor context)
    nonisolated func writeFileSync(relativePath: String, content: String) throws {
        guard let url = activeRepoURLSync else { throw LocalGitError.notCloned }
        let git = LocalGitService(localURL: url)
        try git.writeFile(relativePath: relativePath, content: content)
    }

    /// Delete a file from the active repo (safe to call from non-MainActor context)
    nonisolated func deleteFileSync(relativePath: String) throws {
        guard let url = activeRepoURLSync else { throw LocalGitError.notCloned }
        let git = LocalGitService(localURL: url)
        try git.deleteFile(relativePath: relativePath)
    }

    /// List files in the active repo for context injection
    func listFiles(maxDepth: Int = 3) -> [String] {
        guard let base = activeRepoURL else { return [] }
        var result: [String] = []
        collectFiles(at: base, relativeTo: base, depth: 0, maxDepth: maxDepth, into: &result)
        return result.sorted()
    }

    /// List all cloned repos
    func listRepos() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: reposRoot.path) else { return [] }
        return contents.filter { name in
            var isDir: ObjCBool = false
            let path = reposRoot.appendingPathComponent(name).path
            return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }.sorted()
    }

    /// Switch the active repo to a different cloned repo
    func setActiveRepo(_ name: String) {
        activeRepoName = name
        let git = LocalGitService(localURL: reposRoot.appendingPathComponent(name))
        if git.hasGitDirectory {
            Task {
                if let info = try? await git.repoInfo() {
                    activeRepoBranch = info.branch
                    lastCommitSHA = info.commitSHA
                }
            }
        }
        saveState()
    }

    /// Pending change count
    func pendingChangeCount() async -> Int {
        guard let git = gitService, git.hasGitDirectory else { return 0 }
        return (try? await git.repoInfo().changeCount) ?? 0
    }

    // MARK: - State Persistence

    private func saveState() {
        UserDefaults.standard.set(activeRepoName, forKey: "\(stateKey)_repo")
        UserDefaults.standard.set(activeRepoBranch, forKey: "\(stateKey)_branch")
        UserDefaults.standard.set(lastCommitSHA, forKey: "\(stateKey)_sha")
    }

    private func restoreState() {
        activeRepoName = UserDefaults.standard.string(forKey: "\(stateKey)_repo") ?? ""
        activeRepoBranch = UserDefaults.standard.string(forKey: "\(stateKey)_branch") ?? ""
        lastCommitSHA = UserDefaults.standard.string(forKey: "\(stateKey)_sha") ?? ""
    }

    // MARK: - Helpers

    private func extractRepoName(from url: String) -> String {
        let cleaned = url
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return cleaned.components(separatedBy: "/").last ?? "repo"
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
