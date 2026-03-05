import Foundation

@MainActor
final class GitViewModel: ObservableObject {
    @Published var output: [String] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var repos: [(name: String, fullName: String, isPrivate: Bool)] = []
    @Published var commandInput = ""

    // Clone fields
    @Published var cloneURL = ""
    @Published var selectedProject = ""

    // Commit fields
    @Published var commitMessage = ""

    // Create repo fields
    @Published var newRepoName = ""
    @Published var newRepoDescription = ""
    @Published var newRepoIsPrivate = false

    private let gitService = GitService.shared
    private let fileService = FileService.shared

    var projects: [String] {
        fileService.listProjects()
    }

    var projectsRoot: String {
        fileService.projectsRoot.path
    }

    func executeCommand() {
        let cmd = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }

        commandInput = ""
        output.append("$ \(cmd)")

        Task {
            await processCommand(cmd)
        }
    }

    private func processCommand(_ cmd: String) async {
        let parts = cmd.components(separatedBy: " ").filter { !$0.isEmpty }
        guard let first = parts.first else { return }

        // Normalize: accept both "git clone" and just "clone"
        let command: String
        let args: [String]
        if first == "git" && parts.count > 1 {
            command = parts[1]
            args = Array(parts.dropFirst(2))
        } else {
            command = first
            args = Array(parts.dropFirst())
        }

        isLoading = true
        defer { isLoading = false }

        do {
            switch command {
            case "clone":
                try await handleClone(args)

            case "push":
                try await handlePush(args)

            case "pull":
                try await handlePull(args)

            case "commit":
                try await handleCommit(args)

            case "init":
                handleInit(args)

            case "status":
                handleStatus(args)

            case "repos", "ls-remote":
                try await handleListRepos()

            case "create-repo":
                try await handleCreateRepo(args)

            case "help":
                showHelp()

            default:
                output.append("Unknown command: \(command). Type 'help' for available commands.")
            }
        } catch {
            output.append("❌ Error: \(error.localizedDescription)")
        }

        // Sync git service output
        let serviceOutput = gitService.output
        output.append(contentsOf: serviceOutput)
        gitService.clearOutput()
    }

    // MARK: - Command Handlers

    private func handleClone(_ args: [String]) async throws {
        // Usage: clone owner/repo [branch]
        guard let repoArg = args.first else {
            output.append("Usage: clone <owner/repo> [branch]")
            return
        }

        let parts = repoArg.split(separator: "/")
        guard parts.count == 2 else {
            output.append("Format: owner/repo (e.g., octocat/hello-world)")
            return
        }

        let owner = String(parts[0])
        let repo = String(parts[1])
        let branch = args.count > 1 ? args[1] : "main"
        let projectPath = fileService.projectsRoot.appendingPathComponent(repo).path

        try await gitService.clone(owner: owner, repo: repo, branch: branch, to: projectPath)
    }

    private func handlePush(_ args: [String]) async throws {
        let project = resolveProject(args)
        guard let projectPath = projectPath(for: project) else {
            output.append("Project not found: \(project). Available: \(projects.joined(separator: ", "))")
            return
        }

        let message = commitMessage.isEmpty ? "Update from LocalCoder" : commitMessage
        try await gitService.commitAndPush(projectPath: projectPath, message: message)
        commitMessage = ""
    }

    private func handlePull(_ args: [String]) async throws {
        let project = resolveProject(args)
        guard let projectPath = projectPath(for: project) else {
            output.append("Project not found: \(project)")
            return
        }

        try await gitService.pull(projectPath: projectPath)
    }

    private func handleCommit(_ args: [String]) async throws {
        // commit <project> -m "message"
        guard args.count >= 3, args[1] == "-m" else {
            output.append("Usage: commit <project> -m \"message\"")
            return
        }

        let project = args[0]
        let message = args.dropFirst(2).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        guard let projectPath = projectPath(for: project) else {
            output.append("Project not found: \(project)")
            return
        }

        try await gitService.commitAndPush(projectPath: projectPath, message: message)
    }

    private func handleInit(_ args: [String]) {
        // init <project> <owner/repo>
        guard args.count >= 2 else {
            output.append("Usage: init <project> <owner/repo>")
            return
        }

        let project = args[0]
        let repoParts = args[1].split(separator: "/")
        guard repoParts.count == 2 else {
            output.append("Format: owner/repo")
            return
        }

        let projectPath = fileService.projectsRoot.appendingPathComponent(project).path
        gitService.initRepo(projectPath: projectPath, owner: String(repoParts[0]), repo: String(repoParts[1]))
    }

    private func handleStatus(_ args: [String]) {
        let project = resolveProject(args)
        guard let projectPath = projectPath(for: project) else {
            output.append("Project not found: \(project)")
            return
        }

        if let info = gitService.getRepoInfo(at: projectPath) {
            output.append("Repository: \(info.owner)/\(info.repo)")
            output.append("Branch: \(info.branch)")
        } else {
            output.append("Not a git-tracked project. Use 'init <project> <owner/repo>' to link it.")
        }
    }

    private func handleListRepos() async throws {
        repos = try await gitService.listRepos()
        for repo in repos {
            let visibility = repo.isPrivate ? "🔒" : "🌐"
            output.append("\(visibility) \(repo.fullName)")
        }
    }

    private func handleCreateRepo(_ args: [String]) async throws {
        guard let name = args.first else {
            output.append("Usage: create-repo <name> [--private]")
            return
        }

        let isPrivate = args.contains("--private")
        try await gitService.createRepo(name: name, isPrivate: isPrivate)
    }

    private func showHelp() {
        output.append(contentsOf: [
            "╔══════════════════════════════════════════╗",
            "║        LocalCoder Git Commands           ║",
            "╠══════════════════════════════════════════╣",
            "║ clone <owner/repo> [branch]              ║",
            "║ push <project>                           ║",
            "║ pull <project>                           ║",
            "║ commit <project> -m \"message\"            ║",
            "║ init <project> <owner/repo>              ║",
            "║ status <project>                         ║",
            "║ repos                                    ║",
            "║ create-repo <name> [--private]           ║",
            "║ help                                     ║",
            "╚══════════════════════════════════════════╝",
        ])
    }

    // MARK: - Helpers

    private func resolveProject(_ args: [String]) -> String {
        if let first = args.first, !first.isEmpty { return first }
        if !selectedProject.isEmpty { return selectedProject }
        return projects.first ?? ""
    }

    private func projectPath(for name: String) -> String? {
        let path = fileService.projectsRoot.appendingPathComponent(name).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    func clearOutput() {
        output.removeAll()
    }
}
