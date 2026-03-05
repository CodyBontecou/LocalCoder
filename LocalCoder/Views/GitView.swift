import SwiftUI

struct GitView: View {
    @StateObject private var viewModel = GitViewModel()
    @State private var activeSheet: GitSheet?

    enum GitSheet: Identifiable {
        case clone, push, createRepo, repos
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Quick Actions
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        quickAction("Clone", icon: "arrow.down.doc", color: .blue) {
                            activeSheet = .clone
                        }
                        quickAction("Push", icon: "arrow.up.doc", color: .green) {
                            activeSheet = .push
                        }
                        quickAction("New Repo", icon: "plus.rectangle", color: .purple) {
                            activeSheet = .createRepo
                        }
                        quickAction("My Repos", icon: "list.bullet", color: .orange) {
                            activeSheet = .repos
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(.bar)

                Divider()

                // Terminal
                GitTerminalView(output: viewModel.output, isLoading: viewModel.isLoading)

                // Command input
                commandBar
            }
            .navigationTitle("Git")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { viewModel.clearOutput() }) {
                        Image(systemName: "trash")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .clone: cloneSheet
                case .push: pushSheet
                case .createRepo: createRepoSheet
                case .repos: reposSheet
                }
            }
            .onAppear {
                if viewModel.output.isEmpty {
                    viewModel.output.append("Welcome to LocalCoder Git Terminal")
                    viewModel.output.append("Type 'help' for available commands")
                    viewModel.output.append("")
                }
            }
        }
    }

    // MARK: - Subviews

    private func quickAction(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption.bold())
            }
            .frame(width: 72, height: 64)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(.green)

            TextField("git command...", text: $viewModel.commandInput)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { viewModel.executeCommand() }

            Button(action: { viewModel.executeCommand() }) {
                Image(systemName: "return")
                    .font(.body.bold())
                    .foregroundStyle(.green)
            }
            .disabled(viewModel.commandInput.isEmpty || viewModel.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    // MARK: - Sheets

    private var cloneSheet: some View {
        NavigationStack {
            Form {
                Section("Repository") {
                    TextField("owner/repo", text: $viewModel.cloneURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Text("The repo will be cloned to your Projects folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Clone Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clone") {
                        viewModel.commandInput = "clone \(viewModel.cloneURL)"
                        viewModel.executeCommand()
                        activeSheet = nil
                    }
                    .disabled(viewModel.cloneURL.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var pushSheet: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    Picker("Project", selection: $viewModel.selectedProject) {
                        ForEach(viewModel.projects, id: \.self) { project in
                            Text(project).tag(project)
                        }
                    }
                }

                Section("Commit Message") {
                    TextField("Describe your changes", text: $viewModel.commitMessage, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Push to GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Push") {
                        viewModel.commandInput = "push \(viewModel.selectedProject)"
                        viewModel.executeCommand()
                        activeSheet = nil
                    }
                    .disabled(viewModel.selectedProject.isEmpty)
                }
            }
            .onAppear {
                if viewModel.selectedProject.isEmpty {
                    viewModel.selectedProject = viewModel.projects.first ?? ""
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var createRepoSheet: some View {
        NavigationStack {
            Form {
                Section("Repository Details") {
                    TextField("Repository name", text: $viewModel.newRepoName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Description (optional)", text: $viewModel.newRepoDescription)

                    Toggle("Private", isOn: $viewModel.newRepoIsPrivate)
                }
            }
            .navigationTitle("Create Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let prv = viewModel.newRepoIsPrivate ? " --private" : ""
                        viewModel.commandInput = "create-repo \(viewModel.newRepoName)\(prv)"
                        viewModel.executeCommand()
                        activeSheet = nil
                    }
                    .disabled(viewModel.newRepoName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var reposSheet: some View {
        NavigationStack {
            List {
                if viewModel.repos.isEmpty {
                    ContentUnavailableView("No Repos Loaded", systemImage: "arrow.clockwise", description: Text("Tap refresh to load your repos"))
                } else {
                    ForEach(viewModel.repos, id: \.fullName) { repo in
                        HStack {
                            Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                                .foregroundStyle(repo.isPrivate ? .orange : .green)
                            VStack(alignment: .leading) {
                                Text(repo.name).font(.body.bold())
                                Text(repo.fullName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Clone") {
                                viewModel.commandInput = "clone \(repo.fullName)"
                                viewModel.executeCommand()
                                activeSheet = nil
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                        }
                    }
                }
            }
            .navigationTitle("My Repositories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { activeSheet = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        viewModel.commandInput = "repos"
                        viewModel.executeCommand()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}
