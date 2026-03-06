import SwiftUI

struct SettingsView: View {
    @AppStorage("github_username") private var githubUsername = ""
    @AppStorage("default_project") private var defaultProject = ""
    @AppStorage("git_author_name") private var gitAuthorName = ""
    @AppStorage("git_author_email") private var gitAuthorEmail = ""
    @StateObject private var gitSync = GitSyncManager.shared
    @EnvironmentObject var debugConsole: DebugConsole
    @State private var githubToken: String = ""
    @State private var showToken = false
    @State private var showTokenHelp = false
    @State private var cloneURL = ""
    @State private var cloneError: String?
    @State private var commitMessage = ""
    @State private var showModelManager = false
    @State private var showConversationList = false
    @State private var showDebugPanel = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LC.spacingLG) {
                    // Tools
                    settingsSection("TOOLS") {
                        VStack(spacing: LC.spacingSM) {
                            // Conversation History
                            Button(action: { showConversationList = true }) {
                                toolRow(icon: "clock.arrow.circlepath", label: "CONVERSATION HISTORY", detail: "View past conversations")
                            }

                            // Model Manager
                            Button(action: { showModelManager = true }) {
                                toolRow(icon: "cpu", label: "MODEL MANAGER", detail: "Download and manage AI models")
                            }

                            // Debug Console
                            Button(action: { showDebugPanel = true }) {
                                HStack(spacing: LC.spacingSM) {
                                    Image(systemName: debugConsole.errorCount > 0 ? "ant.circle.fill" : "ant")
                                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                                        .foregroundStyle(debugConsole.errorCount > 0 ? LC.accent : LC.secondary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("DEBUG CONSOLE")
                                            .font(LC.label(10))
                                            .tracking(1)
                                            .foregroundStyle(LC.primary)
                                        Text(debugConsole.errorCount > 0 ? "\(debugConsole.errorCount) error(s)" : "View debug logs")
                                            .font(LC.caption(10))
                                            .foregroundStyle(debugConsole.errorCount > 0 ? LC.accent : LC.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(LC.secondary)
                                }
                                .padding(LC.spacingSM + 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: LC.radiusSM)
                                        .stroke(debugConsole.errorCount > 0 ? LC.accent.opacity(0.3) : LC.border, lineWidth: LC.borderWidth)
                                )
                            }
                        }
                    }

                    // GitHub
                    settingsSection("GITHUB ACCOUNT") {
                        VStack(spacing: LC.spacingSM) {
                            fieldRow(icon: "person", label: "USER") {
                                TextField("Username", text: $githubUsername)
                                    .font(LC.body(14))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }

                            fieldRow(icon: "key", label: "TOKEN") {
                                HStack {
                                    if showToken {
                                        TextField("Personal Access Token", text: $githubToken)
                                            .font(LC.body(14))
                                            .autocorrectionDisabled()
                                            .textInputAutocapitalization(.never)
                                    } else {
                                        SecureField("Personal Access Token", text: $githubToken)
                                            .font(LC.body(14))
                                    }
                                    Button(action: { showToken.toggle() }) {
                                        Image(systemName: showToken ? "eye.slash" : "eye")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(LC.secondary)
                                    }
                                }
                            }
                            .onChange(of: githubToken) { _, newValue in
                                // Save PAT to Keychain (secure) instead of UserDefaults
                                gitSync.pat = newValue
                            }

                            // Token status
                            HStack(spacing: LC.spacingSM) {
                                LCStatusDot(isActive: !githubToken.isEmpty)
                                Text(githubToken.isEmpty ? "TOKEN REQUIRED" : "TOKEN CONFIGURED")
                                    .font(LC.label(9))
                                    .tracking(1)
                                    .foregroundStyle(githubToken.isEmpty ? LC.destructive : LC.accent)
                                Spacer()
                            }
                            .padding(.horizontal, LC.spacingSM)
                            .padding(.vertical, LC.spacingXS)

                            Button(action: { showTokenHelp = true }) {
                                HStack(spacing: LC.spacingSM) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 12, design: .monospaced))
                                    Text("HOW TO GET A TOKEN")
                                        .font(LC.label(9))
                                        .tracking(1)
                                }
                                .foregroundStyle(LC.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(LC.spacingSM)
                            }
                        }
                    }

                    // Git Identity
                    settingsSection("GIT IDENTITY") {
                        VStack(spacing: LC.spacingSM) {
                            fieldRow(icon: "person.text.rectangle", label: "NAME") {
                                TextField("Author Name", text: $gitAuthorName)
                                    .font(LC.body(14))
                                    .autocorrectionDisabled()
                            }

                            fieldRow(icon: "envelope", label: "EMAIL") {
                                TextField("author@example.com", text: $gitAuthorEmail)
                                    .font(LC.body(14))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                            }

                            Text("Used for commit authorship when pushing changes")
                                .font(LC.caption(10))
                                .foregroundStyle(LC.secondary)
                                .padding(.horizontal, LC.spacingSM)
                        }
                    }

                    // Git Repository
                    settingsSection("GIT REPOSITORY") {
                        VStack(spacing: LC.spacingSM) {
                            if gitSync.hasActiveRepo {
                                // Show active repo info
                                VStack(spacing: 0) {
                                    aboutRow("REPO", gitSync.activeRepoName)
                                    Rectangle().fill(LC.border.opacity(0.5)).frame(height: LC.borderWidth)
                                    aboutRow("BRANCH", gitSync.activeRepoBranch)
                                    Rectangle().fill(LC.border.opacity(0.5)).frame(height: LC.borderWidth)
                                    aboutRow("SHA", String(gitSync.lastCommitSHA.prefix(7)))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                                .overlay(
                                    RoundedRectangle(cornerRadius: LC.radiusSM)
                                        .stroke(LC.border, lineWidth: LC.borderWidth)
                                )

                                if !gitSync.statusMessage.isEmpty {
                                    HStack(spacing: LC.spacingSM) {
                                        Image(systemName: "info.circle")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(LC.accent)
                                        Text(gitSync.statusMessage)
                                            .font(LC.caption(11))
                                            .foregroundStyle(LC.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, LC.spacingSM)
                                }

                                // Pull / Push buttons
                                HStack(spacing: LC.spacingSM) {
                                    Button(action: {
                                        Task {
                                            do {
                                                try await gitSync.pull()
                                            } catch {
                                                cloneError = error.localizedDescription
                                            }
                                        }
                                    }) {
                                        HStack(spacing: LC.spacingSM) {
                                            Image(systemName: "arrow.down")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            Text("PULL")
                                                .font(LC.label(10))
                                                .tracking(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, LC.spacingSM)
                                        .foregroundStyle(LC.primary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: LC.radiusSM)
                                                .stroke(LC.border, lineWidth: LC.borderWidth)
                                        )
                                    }
                                    .disabled(gitSync.isPulling)

                                    Button(action: {
                                        let msg = commitMessage.isEmpty ? "Update from LocalCoder" : commitMessage
                                        Task {
                                            do {
                                                try await gitSync.commitAndPush(message: msg)
                                                commitMessage = ""
                                            } catch {
                                                cloneError = error.localizedDescription
                                            }
                                        }
                                    }) {
                                        HStack(spacing: LC.spacingSM) {
                                            Image(systemName: "arrow.up")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            Text("PUSH")
                                                .font(LC.label(10))
                                                .tracking(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, LC.spacingSM)
                                        .foregroundStyle(.white)
                                        .background(LC.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                                    }
                                    .disabled(gitSync.isPushing)
                                }

                                fieldRow(icon: "text.bubble", label: "MSG") {
                                    TextField("Commit message", text: $commitMessage)
                                        .font(LC.body(14))
                                        .autocorrectionDisabled()
                                }
                            }

                            // Clone field
                            fieldRow(icon: "link", label: "URL") {
                                TextField("owner/repo", text: $cloneURL)
                                    .font(LC.body(14))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                            }

                            Button(action: {
                                cloneError = nil
                                Task {
                                    do {
                                        try await gitSync.cloneRepo(remoteURL: cloneURL)
                                        cloneURL = ""
                                    } catch {
                                        cloneError = error.localizedDescription
                                    }
                                }
                            }) {
                                HStack(spacing: LC.spacingSM) {
                                    if gitSync.isCloning {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .tint(LC.accent)
                                    } else {
                                        Image(systemName: "arrow.down.doc")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    }
                                    Text(gitSync.isCloning ? "CLONING..." : "CLONE REPO")
                                        .font(LC.label(10))
                                        .tracking(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, LC.spacingSM)
                                .foregroundStyle(LC.accent)
                                .overlay(
                                    RoundedRectangle(cornerRadius: LC.radiusSM)
                                        .stroke(LC.accent.opacity(0.3), lineWidth: LC.borderWidth)
                                )
                            }
                            .disabled(cloneURL.isEmpty || gitSync.isCloning || githubToken.isEmpty)

                            if let err = cloneError {
                                HStack(spacing: LC.spacingSM) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(LC.destructive)
                                    Text(err)
                                        .font(LC.caption(10))
                                        .foregroundStyle(LC.destructive)
                                    Spacer()
                                }
                                .padding(LC.spacingSM)
                            }

                            Text("Clone a repo to the device. The AI writes files here and you push when ready.")
                                .font(LC.caption(10))
                                .foregroundStyle(LC.secondary)
                                .padding(.horizontal, LC.spacingSM)
                        }
                    }

                    // Defaults
                    settingsSection("DEFAULTS") {
                        fieldRow(icon: "folder", label: "DIR") {
                            TextField("Default Project Name", text: $defaultProject)
                                .font(LC.body(14))
                                .autocorrectionDisabled()
                        }

                        Text("Default folder for saving generated code")
                            .font(LC.caption(10))
                            .foregroundStyle(LC.secondary)
                            .padding(.horizontal, LC.spacingSM)
                    }

                    // Storage
                    settingsSection("STORAGE") {
                        VStack(spacing: 0) {
                            storageRow("MODELS", path: ModelManager.shared.modelsDirectory.path)
                            Rectangle().fill(LC.border.opacity(0.5)).frame(height: LC.borderWidth)
                            storageRow("PROJECTS", path: FileService.shared.projectsRoot.path)
                            Rectangle().fill(LC.border.opacity(0.5)).frame(height: LC.borderWidth)
                            storageRow("REPOS", path: gitSync.reposRoot.path)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                        .overlay(
                            RoundedRectangle(cornerRadius: LC.radiusSM)
                                .stroke(LC.border, lineWidth: LC.borderWidth)
                        )
                    }

                    // About
                    settingsSection("ABOUT") {
                        VStack(spacing: 0) {
                            aboutRow("VERSION", "1.0.0")
                            Rectangle().fill(LC.border.opacity(0.5)).frame(height: LC.borderWidth)
                            aboutRow("ENGINE", "MLX")
                            Rectangle().fill(LC.border.opacity(0.5)).frame(height: LC.borderWidth)
                            aboutRow("RUNTIME", "mlx-swift-lm")
                        }
                        .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                        .overlay(
                            RoundedRectangle(cornerRadius: LC.radiusSM)
                                .stroke(LC.border, lineWidth: LC.borderWidth)
                        )

                        Link(destination: URL(string: "https://github.com/ml-explore/mlx-swift-lm")!) {
                            HStack(spacing: LC.spacingSM) {
                                Text("GITHUB")
                                    .font(LC.label(9))
                                    .tracking(1)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(LC.accent)
                            .padding(LC.spacingSM + 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: LC.radiusSM)
                                    .stroke(LC.accent.opacity(0.3), lineWidth: LC.borderWidth)
                            )
                        }
                    }
                }
                .padding(LC.spacingMD)
            }
            .background(LC.surface)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SYSTEM")
                        .font(LC.label(12))
                        .tracking(2)
                        .foregroundStyle(LC.primary)
                }
            }
            .toolbarBackground(LC.surfaceElevated, for: .navigationBar)
            .onAppear {
                // Load PAT from Keychain
                githubToken = KeychainService.load(key: "github_pat") ?? ""
                // Migrate from old UserDefaults storage if needed
                if githubToken.isEmpty, let oldToken = UserDefaults.standard.string(forKey: "github_token"), !oldToken.isEmpty {
                    githubToken = oldToken
                    gitSync.pat = oldToken
                    UserDefaults.standard.removeObject(forKey: "github_token")
                }
            }
            .sheet(isPresented: $showTokenHelp) {
                tokenHelpSheet
            }
            .sheet(isPresented: $showModelManager) {
                NavigationStack {
                    ModelManagerView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showModelManager = false }
                                    .font(LC.body(14))
                                    .foregroundStyle(LC.accent)
                            }
                        }
                }
            }
            .sheet(isPresented: $showConversationList) {
                ConversationListView(viewModel: ChatViewModel())
            }
            .sheet(isPresented: $showDebugPanel) {
                NavigationStack {
                    DebugPanelView(console: debugConsole, isExpanded: .constant(true))
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Text("DEBUG CONSOLE")
                                    .font(LC.label(12))
                                    .tracking(2)
                                    .foregroundStyle(LC.primary)
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showDebugPanel = false }
                                    .font(LC.body(14))
                                    .foregroundStyle(LC.accent)
                            }
                        }
                        .toolbarBackground(LC.surfaceElevated, for: .navigationBar)
                }
            }
        }
    }

    // MARK: - Components

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LC.spacingSM) {
            Text(title)
                .font(LC.label(10))
                .tracking(2)
                .foregroundStyle(LC.secondary)
                .padding(.leading, 2)

            VStack(spacing: LC.spacingSM) {
                content()
            }
        }
    }

    private func fieldRow<Content: View>(icon: String, label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: LC.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(LC.secondary)
                .frame(width: 16)

            Text(label)
                .font(LC.label(9))
                .tracking(1)
                .foregroundStyle(LC.secondary)
                .frame(width: 44, alignment: .leading)

            content()
        }
        .padding(LC.spacingSM + 2)
        .overlay(
            RoundedRectangle(cornerRadius: LC.radiusSM)
                .stroke(LC.border, lineWidth: LC.borderWidth)
        )
    }

    private func storageRow(_ title: String, path: String) -> some View {
        HStack {
            Text(title)
                .font(LC.label(9))
                .tracking(1)
                .foregroundStyle(LC.secondary)
            Spacer()
            Text(directorySize(path))
                .font(LC.caption(12))
                .foregroundStyle(LC.primary)
        }
        .padding(LC.spacingSM + 2)
    }

    private func toolRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: LC.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(LC.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(LC.label(10))
                    .tracking(1)
                    .foregroundStyle(LC.primary)
                Text(detail)
                    .font(LC.caption(10))
                    .foregroundStyle(LC.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(LC.secondary)
        }
        .padding(LC.spacingSM + 2)
        .overlay(
            RoundedRectangle(cornerRadius: LC.radiusSM)
                .stroke(LC.border, lineWidth: LC.borderWidth)
        )
    }

    private func aboutRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(LC.label(9))
                .tracking(1)
                .foregroundStyle(LC.secondary)
            Spacer()
            Text(value)
                .font(LC.caption(12))
                .foregroundStyle(LC.primary)
        }
        .padding(LC.spacingSM + 2)
    }

    private func directorySize(_ path: String) -> String {
        guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 B"
        }
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }

    // MARK: - Token Help

    private var tokenHelpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LC.spacingMD) {
                    Text("CREATING A GITHUB\nPERSONAL ACCESS TOKEN")
                        .font(LC.heading(15))
                        .foregroundStyle(LC.primary)

                    VStack(alignment: .leading, spacing: LC.spacingMD) {
                        step(1, "Go to GitHub.com → Settings")
                        step(2, "Click 'Developer settings'")
                        step(3, "Personal access tokens → Tokens (classic)")
                        step(4, "Generate new token (classic)")
                        step(5, "Name it 'LocalCoder'")
                        step(6, "Select scope: 'repo'")
                        step(7, "Generate token")
                        step(8, "Paste token in Settings")
                    }

                    HStack(spacing: LC.spacingSM) {
                        Rectangle()
                            .fill(LC.accent)
                            .frame(width: 3)

                        VStack(alignment: .leading, spacing: LC.spacingXS) {
                            Text("IMPORTANT")
                                .font(LC.label(9))
                                .tracking(1.5)
                                .foregroundStyle(LC.accent)
                            Text("Keep your token secret. It grants access to your GitHub account. Stored securely in Keychain on-device only.")
                                .font(LC.caption(11))
                                .foregroundStyle(LC.secondary)
                        }
                    }
                    .padding(LC.spacingSM + 2)
                    .background(LC.accent.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                }
                .padding(LC.spacingMD)
            }
            .background(LC.surface)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showTokenHelp = false }
                        .font(LC.body(14))
                        .foregroundStyle(LC.accent)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: LC.spacingMD - 4) {
            Text("\(number)")
                .font(LC.label(10))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(LC.accent)
                .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))

            Text(text)
                .font(LC.body(13))
                .foregroundStyle(LC.primary)
        }
    }
}
