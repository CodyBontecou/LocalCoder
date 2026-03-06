import SwiftUI

// MARK: - Activity Log

struct GitActivity: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let type: ActivityType

    enum ActivityType {
        case success, error, info
    }
}

// MARK: - Git View

struct GitView: View {
    @StateObject private var gitSync = GitSyncManager.shared
    @StateObject private var auth = GitHubAuthService.shared
    @State private var commitMessage = ""
    @State private var changedFiles: [ChangedFile] = []
    @State private var activities: [GitActivity] = []
    @State private var activeSheet: GitSheet?
    @State private var showAuthOptions = false
    @State private var patInput = ""
    @State private var cloneURL = ""
    @State private var showChangedFiles = false
    @State private var githubRepos: [GitHubAuthService.GitHubRepo] = []
    @State private var repoSearchText = ""
    @State private var isLoadingRepos = false
    @State private var refreshTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    enum GitSheet: Identifiable {
        case clone, repos
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LC.spacingLG) {
                    authSection
                    repoSection
                    if gitSync.hasActiveRepo {
                        changesSection
                        commitSection
                        actionsSection
                    }
                    moreActionsSection
                    if !activities.isEmpty {
                        activitySection
                    }
                }
                .padding(LC.spacingMD)
            }
            .background(LC.surface)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("GIT")
                        .font(LC.label(12))
                        .tracking(2)
                        .foregroundStyle(LC.primary)
                }
            }
            .toolbarBackground(LC.surfaceElevated, for: .navigationBar)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .clone: cloneSheet
                case .repos: reposSheet
                }
            }
            .onAppear { refreshStatus() }
            .onDisappear { refreshTask?.cancel() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    auth.resumePollingIfNeeded()
                }
            }
        }
    }

    // MARK: - Auth Section

    private var authSection: some View {
        Group {
            switch auth.state {
            case .signedOut:
                signedOutBanner
            case .authenticating:
                authenticatingBanner
            case .deviceFlow(let userCode, let verificationURL):
                deviceFlowBanner(userCode: userCode, verificationURL: verificationURL)
            case .authenticated:
                authenticatedBanner
            case .error(let message):
                errorBanner(message)
            }
        }
    }

    private var signedOutBanner: some View {
        VStack(spacing: LC.spacingSM) {
            HStack(spacing: LC.spacingSM) {
                Image(systemName: "key.slash")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(LC.secondary)
                Text("NOT AUTHENTICATED")
                    .font(LC.label(10))
                    .tracking(1.5)
                    .foregroundStyle(LC.secondary)
                Spacer()
            }

            if showAuthOptions {
                authOptionsView
            } else {
                HStack(spacing: LC.spacingSM) {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAuthOptions = true } }) {
                        HStack(spacing: LC.spacingSM) {
                            Image(systemName: "person.badge.key")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            Text("SIGN IN")
                                .font(LC.label(10))
                                .tracking(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LC.spacingSM + 2)
                        .foregroundStyle(.white)
                        .background(LC.accent)
                        .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                    }
                }
            }
        }
        .padding(LC.spacingMD)
        .overlay(
            RoundedRectangle(cornerRadius: LC.radiusSM)
                .stroke(LC.border, lineWidth: LC.borderWidth)
        )
    }

    private var authOptionsView: some View {
        VStack(spacing: LC.spacingSM) {
            // PAT option
            VStack(spacing: LC.spacingSM) {
                HStack(spacing: LC.spacingSM) {
                    Image(systemName: "key")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(LC.secondary)
                        .frame(width: 16)
                    Text("TOKEN")
                        .font(LC.label(9))
                        .tracking(1)
                        .foregroundStyle(LC.secondary)
                        .frame(width: 50, alignment: .leading)
                    SecureField("Personal Access Token", text: $patInput)
                        .font(LC.body(14))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(LC.spacingSM + 2)
                .overlay(
                    RoundedRectangle(cornerRadius: LC.radiusSM)
                        .stroke(LC.border, lineWidth: LC.borderWidth)
                )

                Button(action: {
                    Task {
                        await auth.signInWithPAT(patInput)
                        if auth.isAuthenticated { patInput = "" }
                    }
                }) {
                    Text("SIGN IN WITH TOKEN")
                        .font(LC.label(10))
                        .tracking(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LC.spacingSM + 2)
                        .foregroundStyle(.white)
                        .background(patInput.isEmpty ? LC.secondary.opacity(0.3) : LC.accent)
                        .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                }
                .disabled(patInput.isEmpty)
            }

            // Divider
            HStack(spacing: LC.spacingSM) {
                Rectangle().fill(LC.border).frame(height: LC.borderWidth)
                Text("OR")
                    .font(LC.label(9))
                    .tracking(1)
                    .foregroundStyle(LC.secondary)
                Rectangle().fill(LC.border).frame(height: LC.borderWidth)
            }

            // OAuth option
            Button(action: {
                Task { await auth.startDeviceFlow() }
            }) {
                HStack(spacing: LC.spacingSM) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text("SIGN IN WITH GITHUB")
                        .font(LC.label(10))
                        .tracking(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, LC.spacingSM + 2)
                .foregroundStyle(auth.hasOAuthConfigured ? LC.primary : LC.secondary.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: LC.radiusSM)
                        .stroke(auth.hasOAuthConfigured ? LC.border : LC.border.opacity(0.3), lineWidth: LC.borderWidth)
                )
            }
            .disabled(!auth.hasOAuthConfigured)

            if !auth.hasOAuthConfigured {
                Text("OAuth requires a Client ID — use a token instead")
                    .font(LC.caption(10))
                    .foregroundStyle(LC.secondary)
            }

            // Cancel
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAuthOptions = false } }) {
                Text("CANCEL")
                    .font(LC.label(9))
                    .tracking(1)
                    .foregroundStyle(LC.secondary)
            }
        }
    }

    private var authenticatingBanner: some View {
        HStack(spacing: LC.spacingSM) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(LC.accent)
            Text("AUTHENTICATING...")
                .font(LC.label(10))
                .tracking(1.5)
                .foregroundStyle(LC.accent)
            Spacer()
        }
        .padding(LC.spacingMD)
        .overlay(
            RoundedRectangle(cornerRadius: LC.radiusSM)
                .stroke(LC.accent.opacity(0.3), lineWidth: LC.borderWidth)
        )
    }

    private func deviceFlowBanner(userCode: String, verificationURL: String) -> some View {
        VStack(spacing: LC.spacingSM) {
            HStack(spacing: LC.spacingSM) {
                Image(systemName: "globe")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(LC.accent)
                Text("ENTER CODE ON GITHUB")
                    .font(LC.label(10))
                    .tracking(1.5)
                    .foregroundStyle(LC.accent)
                Spacer()
            }

            // User code display
            HStack(spacing: 0) {
                ForEach(Array(userCode.enumerated()), id: \.offset) { _, char in
                    Text(String(char))
                        .font(LC.display(24))
                        .foregroundStyle(char == "-" ? LC.secondary : LC.primary)
                        .frame(width: char == "-" ? 16 : 28)
                }
            }
            .padding(.vertical, LC.spacingSM)

            Button(action: {
                UIPasteboard.general.string = userCode
            }) {
                HStack(spacing: LC.spacingXS) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, design: .monospaced))
                    Text("COPY CODE")
                        .font(LC.label(9))
                        .tracking(1)
                }
                .foregroundStyle(LC.accent)
            }

            if let url = URL(string: verificationURL) {
                Link(destination: url) {
                    HStack(spacing: LC.spacingSM) {
                        Text("OPEN GITHUB.COM/LOGIN/DEVICE")
                            .font(LC.label(10))
                            .tracking(1)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LC.spacingSM + 2)
                    .foregroundStyle(.white)
                    .background(LC.accent)
                    .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                }
            }

            HStack(spacing: LC.spacingSM) {
                ProgressView()
                    .scaleEffect(0.5)
                    .tint(LC.secondary)
                Text("Waiting for authorization...")
                    .font(LC.caption(10))
                    .foregroundStyle(LC.secondary)
                Spacer()
            }

            Button(action: { auth.cancelDeviceFlow() }) {
                Text("CANCEL")
                    .font(LC.label(9))
                    .tracking(1)
                    .foregroundStyle(LC.secondary)
            }
        }
        .padding(LC.spacingMD)
        .background(LC.accent.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: LC.radiusSM)
                .stroke(LC.accent.opacity(0.3), lineWidth: LC.borderWidth)
        )
    }

    private var authenticatedBanner: some View {
        HStack(spacing: LC.spacingSM) {
            LCStatusDot(isActive: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("@\(auth.username.isEmpty ? "authenticated" : auth.username)")
                    .font(LC.body(13))
                    .foregroundStyle(LC.primary)
                Text("via \(auth.method == .oauth ? "GitHub OAuth" : "Personal Access Token")")
                    .font(LC.caption(10))
                    .foregroundStyle(LC.secondary)
            }

            Spacer()

            Button(action: { auth.signOut() }) {
                Text("SIGN OUT")
                    .font(LC.label(9))
                    .tracking(1)
                    .foregroundStyle(LC.secondary)
                    .padding(.horizontal, LC.spacingSM)
                    .padding(.vertical, LC.spacingXS + 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: LC.radiusSM)
                            .stroke(LC.border, lineWidth: LC.borderWidth)
                    )
            }
        }
        .padding(LC.spacingMD)
        .overlay(
            RoundedRectangle(cornerRadius: LC.radiusSM)
                .stroke(LC.border, lineWidth: LC.borderWidth)
        )
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: LC.spacingSM) {
            HStack(spacing: LC.spacingSM) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(LC.destructive)
                Text(message)
                    .font(LC.caption(11))
                    .foregroundStyle(LC.destructive)
                Spacer()
            }

            HStack(spacing: LC.spacingSM) {
                Button(action: { auth.signOut() }) {
                    Text("DISMISS")
                        .font(LC.label(9))
                        .tracking(1)
                        .foregroundStyle(LC.secondary)
                }
                Spacer()
            }
        }
        .padding(LC.spacingMD)
        .background(LC.destructive.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: LC.radiusSM)
                .stroke(LC.destructive.opacity(0.3), lineWidth: LC.borderWidth)
        )
    }

    // MARK: - Repository Section

    private var repoSection: some View {
        VStack(alignment: .leading, spacing: LC.spacingSM) {
            Text("REPOSITORY")
                .font(LC.label(10))
                .tracking(2)
                .foregroundStyle(LC.secondary)
                .padding(.leading, 2)

            if gitSync.hasActiveRepo {
                VStack(spacing: 0) {
                    // Repo name + branch
                    HStack(spacing: LC.spacingSM) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(LC.accent)
                        Text(gitSync.activeRepoName)
                            .font(LC.body(14))
                            .foregroundStyle(LC.primary)
                        Text("/")
                            .font(LC.body(14))
                            .foregroundStyle(LC.secondary)
                        Text(gitSync.activeRepoBranch)
                            .font(LC.body(14))
                            .foregroundStyle(LC.accent)
                        Spacer()
                    }
                    .padding(LC.spacingSM + 2)

                    Rectangle().fill(LC.border.opacity(0.5)).frame(height: LC.borderWidth)

                    // SHA + status
                    HStack(spacing: LC.spacingSM) {
                        Text(String(gitSync.lastCommitSHA.prefix(7)))
                            .font(LC.code(11))
                            .foregroundStyle(LC.secondary)

                        if !gitSync.statusMessage.isEmpty {
                            Text("·")
                                .foregroundStyle(LC.border)
                            Text(gitSync.statusMessage)
                                .font(LC.caption(11))
                                .foregroundStyle(LC.secondary)
                        }
                        Spacer()

                        if gitSync.isStaging || gitSync.isCommitting || gitSync.isPushing || gitSync.isPulling {
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(LC.accent)
                        }
                    }
                    .padding(LC.spacingSM + 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                .overlay(
                    RoundedRectangle(cornerRadius: LC.radiusSM)
                        .stroke(LC.border, lineWidth: LC.borderWidth)
                )
            } else {
                VStack(spacing: LC.spacingSM) {
                    HStack(spacing: LC.spacingSM) {
                        Image(systemName: "questionmark.folder")
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(LC.secondary)
                        Text("No repository active")
                            .font(LC.body(13))
                            .foregroundStyle(LC.secondary)
                        Spacer()
                    }

                    Button(action: { activeSheet = .clone }) {
                        HStack(spacing: LC.spacingSM) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("CLONE A REPOSITORY")
                                .font(LC.label(10))
                                .tracking(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LC.spacingSM + 2)
                        .foregroundStyle(LC.accent)
                        .overlay(
                            RoundedRectangle(cornerRadius: LC.radiusSM)
                                .stroke(LC.accent.opacity(0.3), lineWidth: LC.borderWidth)
                        )
                    }
                }
                .padding(LC.spacingMD)
                .overlay(
                    RoundedRectangle(cornerRadius: LC.radiusSM)
                        .stroke(LC.border, lineWidth: LC.borderWidth)
                )
            }
        }
    }

    // MARK: - Changes Section

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: LC.spacingSM) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { showChangedFiles.toggle() }
                if showChangedFiles { refreshStatus() }
            }) {
                HStack(spacing: LC.spacingSM) {
                    Text("CHANGES")
                        .font(LC.label(10))
                        .tracking(2)
                        .foregroundStyle(LC.secondary)
                        .padding(.leading, 2)

                    if !changedFiles.isEmpty {
                        Text("\(changedFiles.count)")
                            .font(LC.label(9))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(LC.accent)
                            .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                    }

                    Spacer()

                    Image(systemName: showChangedFiles ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(LC.secondary)

                    Button(action: { refreshStatus() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(LC.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if showChangedFiles {
                if changedFiles.isEmpty {
                    HStack(spacing: LC.spacingSM) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(LC.accent)
                        Text("Working tree clean")
                            .font(LC.caption(11))
                            .foregroundStyle(LC.secondary)
                        Spacer()
                    }
                    .padding(LC.spacingSM + 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: LC.radiusSM)
                            .stroke(LC.border, lineWidth: LC.borderWidth)
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(changedFiles) { file in
                            HStack(spacing: LC.spacingSM) {
                                Text(file.status.rawValue)
                                    .font(LC.code(11))
                                    .foregroundStyle(statusColor(for: file.status))
                                    .frame(width: 16)

                                Text(file.path)
                                    .font(LC.code(11))
                                    .foregroundStyle(LC.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                if file.staged {
                                    Text("STAGED")
                                        .font(LC.label(7))
                                        .tracking(0.5)
                                        .foregroundStyle(LC.accent)
                                }
                            }
                            .padding(.horizontal, LC.spacingSM + 2)
                            .padding(.vertical, LC.spacingSM)

                            if file.id != changedFiles.last?.id {
                                Rectangle().fill(LC.border.opacity(0.3)).frame(height: LC.borderWidth)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                    .overlay(
                        RoundedRectangle(cornerRadius: LC.radiusSM)
                            .stroke(LC.border, lineWidth: LC.borderWidth)
                    )
                }
            }
        }
    }

    // MARK: - Commit Message Section

    private var commitSection: some View {
        VStack(alignment: .leading, spacing: LC.spacingSM) {
            Text("COMMIT MESSAGE")
                .font(LC.label(10))
                .tracking(2)
                .foregroundStyle(LC.secondary)
                .padding(.leading, 2)

            TextField("Describe your changes...", text: $commitMessage, axis: .vertical)
                .font(LC.body(14))
                .lineLimit(2...4)
                .padding(LC.spacingSM + 2)
                .overlay(
                    RoundedRectangle(cornerRadius: LC.radiusSM)
                        .stroke(LC.border, lineWidth: LC.borderWidth)
                )
        }
    }

    // MARK: - Quick Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: LC.spacingSM) {
            Text("ACTIONS")
                .font(LC.label(10))
                .tracking(2)
                .foregroundStyle(LC.secondary)
                .padding(.leading, 2)

            // 2x2 grid
            VStack(spacing: LC.spacingSM) {
                HStack(spacing: LC.spacingSM) {
                    gitActionButton(
                        title: "ADD ALL",
                        icon: "plus.circle",
                        style: .secondary,
                        isLoading: gitSync.isStaging,
                        disabled: !auth.isAuthenticated || changedFiles.isEmpty
                    ) {
                        await performAction("Stage all changes") {
                            try await gitSync.stageAll()
                        }
                    }

                    gitActionButton(
                        title: "COMMIT",
                        icon: "checkmark.circle",
                        style: .secondary,
                        isLoading: gitSync.isCommitting,
                        disabled: !auth.isAuthenticated || changedFiles.isEmpty
                    ) {
                        let msg = commitMessage.isEmpty ? "Update from LocalCoder" : commitMessage
                        await performAction("Commit: \(msg)") {
                            try await gitSync.commitOnly(message: msg)
                            commitMessage = ""
                        }
                    }
                }

                HStack(spacing: LC.spacingSM) {
                    gitActionButton(
                        title: "PULL",
                        icon: "arrow.down",
                        style: .secondary,
                        isLoading: gitSync.isPulling,
                        disabled: !auth.isAuthenticated
                    ) {
                        await performAction("Pull from remote") {
                            try await gitSync.pull()
                        }
                    }

                    gitActionButton(
                        title: "PUSH",
                        icon: "arrow.up",
                        style: .primary,
                        isLoading: gitSync.isPushing,
                        disabled: !auth.isAuthenticated
                    ) {
                        await performAction("Push to remote") {
                            try await gitSync.pushOnly()
                        }
                    }
                }
            }
        }
    }

    private func gitActionButton(
        title: String,
        icon: String,
        style: ActionStyle,
        isLoading: Bool,
        disabled: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button(action: {
            Task { await action() }
        }) {
            HStack(spacing: LC.spacingSM) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(style == .primary ? .white : LC.accent)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                Text(title)
                    .font(LC.label(10))
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LC.spacingSM + 4)
            .foregroundStyle(style == .primary ? .white : LC.primary)
            .background(style == .primary ? LC.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
            .overlay(
                RoundedRectangle(cornerRadius: LC.radiusSM)
                    .stroke(style == .primary ? LC.accent : LC.border, lineWidth: LC.borderWidth)
            )
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled || isLoading)
    }

    enum ActionStyle {
        case primary, secondary
    }

    // MARK: - More Actions

    private var moreActionsSection: some View {
        VStack(alignment: .leading, spacing: LC.spacingSM) {
            Text("MORE")
                .font(LC.label(10))
                .tracking(2)
                .foregroundStyle(LC.secondary)
                .padding(.leading, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LC.spacingSM) {
                    moreActionButton("CLONE", icon: "arrow.down.doc") { activeSheet = .clone }
                    moreActionButton("REPOS", icon: "list.bullet") { activeSheet = .repos }

                    if !gitSync.listRepos().isEmpty {
                        Menu {
                            ForEach(gitSync.listRepos(), id: \.self) { repo in
                                Button(action: {
                                    gitSync.setActiveRepo(repo)
                                    refreshStatus()
                                }) {
                                    HStack {
                                        Text(repo)
                                        if repo == gitSync.activeRepoName {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: LC.spacingXS + 2) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 12, design: .monospaced))
                                Text("SWITCH")
                                    .font(LC.label(9))
                                    .tracking(1)
                            }
                            .foregroundStyle(LC.primary)
                            .padding(.horizontal, LC.spacingMD - 4)
                            .padding(.vertical, LC.spacingSM)
                            .overlay(
                                RoundedRectangle(cornerRadius: LC.radiusSM)
                                    .stroke(LC.border, lineWidth: LC.borderWidth)
                            )
                        }
                    }
                }
            }
        }
    }

    private func moreActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: LC.spacingXS + 2) {
                Image(systemName: icon)
                    .font(.system(size: 12, design: .monospaced))
                Text(title)
                    .font(LC.label(9))
                    .tracking(1)
            }
            .foregroundStyle(LC.primary)
            .padding(.horizontal, LC.spacingMD - 4)
            .padding(.vertical, LC.spacingSM)
            .overlay(
                RoundedRectangle(cornerRadius: LC.radiusSM)
                    .stroke(LC.border, lineWidth: LC.borderWidth)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Activity Log

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: LC.spacingSM) {
            HStack {
                Text("ACTIVITY")
                    .font(LC.label(10))
                    .tracking(2)
                    .foregroundStyle(LC.secondary)
                    .padding(.leading, 2)
                Spacer()
                Button(action: { activities.removeAll() }) {
                    Text("CLEAR")
                        .font(LC.label(8))
                        .tracking(1)
                        .foregroundStyle(LC.secondary)
                }
            }

            VStack(spacing: 0) {
                ForEach(activities.suffix(10).reversed()) { activity in
                    HStack(spacing: LC.spacingSM) {
                        Image(systemName: activity.type == .success ? "checkmark.circle.fill" :
                                activity.type == .error ? "xmark.circle.fill" : "info.circle.fill")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(
                                activity.type == .success ? LC.accent :
                                activity.type == .error ? LC.destructive : LC.secondary
                            )

                        Text(activity.message)
                            .font(LC.caption(11))
                            .foregroundStyle(LC.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(activity.timestamp, style: .time)
                            .font(LC.caption(9))
                            .foregroundStyle(LC.secondary)
                    }
                    .padding(.horizontal, LC.spacingSM + 2)
                    .padding(.vertical, LC.spacingSM)

                    if activity.id != activities.suffix(10).reversed().last?.id {
                        Rectangle().fill(LC.border.opacity(0.3)).frame(height: LC.borderWidth)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
            .overlay(
                RoundedRectangle(cornerRadius: LC.radiusSM)
                    .stroke(LC.border, lineWidth: LC.borderWidth)
            )
        }
    }

    // MARK: - Sheets

    private var filteredRepos: [GitHubAuthService.GitHubRepo] {
        if repoSearchText.isEmpty { return githubRepos }
        let query = repoSearchText.lowercased()
        return githubRepos.filter {
            $0.fullName.lowercased().contains(query) ||
            ($0.description?.lowercased().contains(query) ?? false)
        }
    }

    private var cloneSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Search / manual entry field
                VStack(alignment: .leading, spacing: LC.spacingSM) {
                    Text("REPOSITORY")
                        .lcLabel()

                    HStack(spacing: LC.spacingSM) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(LC.secondary)
                            .frame(width: 16)
                        TextField("Search or enter owner/repo", text: $cloneURL)
                            .font(LC.body(14))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .onChange(of: cloneURL) { _, newValue in
                                repoSearchText = newValue
                            }
                    }
                    .padding(LC.spacingSM + 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: LC.radiusSM)
                            .stroke(LC.border, lineWidth: LC.borderWidth)
                    )

                    Text("Select a repo or type owner/repo manually.")
                        .font(LC.caption(11))
                        .foregroundStyle(LC.secondary)
                }
                .padding(LC.spacingMD)

                Rectangle().fill(LC.border.opacity(0.5)).frame(height: LC.borderWidth)

                // Repo list
                if isLoadingRepos {
                    VStack(spacing: LC.spacingSM) {
                        ProgressView()
                            .tint(LC.accent)
                        Text("LOADING REPOS...")
                            .font(LC.label(9))
                            .tracking(1)
                            .foregroundStyle(LC.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if githubRepos.isEmpty && auth.isAuthenticated {
                    VStack(spacing: LC.spacingSM) {
                        Image(systemName: "folder")
                            .font(.system(size: 20, weight: .ultraLight, design: .monospaced))
                            .foregroundStyle(LC.secondary)
                        Text("NO REPOS FOUND")
                            .font(LC.label(10))
                            .tracking(1)
                            .foregroundStyle(LC.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredRepos) { repo in
                                Button(action: {
                                    cloneURL = repo.fullName
                                    repoSearchText = repo.fullName
                                }) {
                                    HStack(spacing: LC.spacingSM) {
                                        Image(systemName: repo.isPrivate ? "lock.fill" : "folder.fill")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(repo.isPrivate ? LC.secondary : LC.accent)
                                            .frame(width: 18)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(repo.fullName)
                                                .font(LC.body(13))
                                                .foregroundStyle(LC.primary)
                                                .lineLimit(1)

                                            if let desc = repo.description, !desc.isEmpty {
                                                Text(desc)
                                                    .font(LC.caption(10))
                                                    .foregroundStyle(LC.secondary)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()

                                        if cloneURL == repo.fullName {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundStyle(LC.accent)
                                        }
                                    }
                                    .padding(.horizontal, LC.spacingMD)
                                    .padding(.vertical, LC.spacingSM + 2)
                                }
                                .buttonStyle(.plain)

                                Rectangle().fill(LC.border.opacity(0.3)).frame(height: LC.borderWidth)
                            }
                        }
                    }
                }
            }
            .background(LC.surfaceElevated)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("CLONE")
                        .font(LC.label(12))
                        .tracking(2)
                        .foregroundStyle(LC.primary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cloneURL = ""
                        repoSearchText = ""
                        activeSheet = nil
                    }
                    .font(LC.body(14))
                    .foregroundStyle(LC.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clone") {
                        let url = cloneURL
                        cloneURL = ""
                        repoSearchText = ""
                        activeSheet = nil
                        Task {
                            await performAction("Clone \(url)") {
                                try await gitSync.cloneRepo(remoteURL: url)
                            }
                            refreshStatus()
                        }
                    }
                    .font(LC.body(14))
                    .foregroundStyle(LC.accent)
                    .disabled(cloneURL.isEmpty || !auth.isAuthenticated)
                }
            }
            .onAppear {
                loadRepos()
            }
        }
        .presentationDetents([.large])
    }

    private func loadRepos() {
        guard auth.isAuthenticated, githubRepos.isEmpty else { return }
        isLoadingRepos = true
        Task {
            do {
                githubRepos = try await auth.fetchUserRepos()
            } catch {
                activities.append(GitActivity(message: "Failed to load repos: \(error.localizedDescription)", type: .error))
            }
            isLoadingRepos = false
        }
    }

    private var reposSheet: some View {
        NavigationStack {
            ScrollView {
                let repos = gitSync.listRepos()
                if repos.isEmpty {
                    VStack(spacing: LC.spacingMD) {
                        Image(systemName: "folder")
                            .font(.system(size: 24, weight: .ultraLight, design: .monospaced))
                            .foregroundStyle(LC.secondary)
                        Text("NO LOCAL REPOS")
                            .font(LC.label(11))
                            .tracking(1.5)
                            .foregroundStyle(LC.secondary)
                        Text("Clone a repo to get started")
                            .font(LC.caption(11))
                            .foregroundStyle(LC.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, LC.spacingXL * 2)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(repos, id: \.self) { repo in
                            Button(action: {
                                gitSync.setActiveRepo(repo)
                                refreshStatus()
                                activeSheet = nil
                            }) {
                                HStack(spacing: LC.spacingSM) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(LC.accent)
                                        .frame(width: 20)

                                    Text(repo)
                                        .font(LC.body(13))
                                        .foregroundStyle(LC.primary)

                                    Spacer()

                                    if repo == gitSync.activeRepoName {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundStyle(LC.accent)
                                    }
                                }
                                .padding(.vertical, LC.spacingSM + 2)
                                .padding(.horizontal, LC.spacingMD)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(LC.border.opacity(0.5)).frame(height: LC.borderWidth)
                            }
                        }
                    }
                }
            }
            .background(LC.surface)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("LOCAL REPOS")
                        .font(LC.label(12))
                        .tracking(2)
                        .foregroundStyle(LC.primary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { activeSheet = nil }
                        .font(LC.body(14))
                        .foregroundStyle(LC.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func refreshStatus() {
        refreshTask?.cancel()
        refreshTask = Task {
            let files = await gitSync.changedFiles()
            if !Task.isCancelled {
                changedFiles = files
            }
        }
    }

    private func performAction(_ description: String, action: () async throws -> Void) async {
        do {
            try await action()
            activities.append(GitActivity(message: description, type: .success))
            refreshStatus()
        } catch {
            activities.append(GitActivity(message: "\(description): \(error.localizedDescription)", type: .error))
        }
    }

    private func statusColor(for status: ChangedFile.ChangeStatus) -> Color {
        switch status {
        case .added, .untracked: return LC.accent
        case .modified: return Color.orange
        case .deleted: return LC.destructive
        case .renamed: return Color.purple
        }
    }
}
