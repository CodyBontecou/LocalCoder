import SwiftUI

struct SettingsView: View {
    @AppStorage("github_token") private var githubToken = ""
    @AppStorage("github_username") private var githubUsername = ""
    @AppStorage("default_project") private var defaultProject = ""
    @State private var showToken = false
    @State private var showTokenHelp = false

    var body: some View {
        NavigationStack {
            List {
                // GitHub Settings
                Section {
                    HStack {
                        Image(systemName: "person.circle")
                            .foregroundStyle(.secondary)
                        TextField("GitHub Username", text: $githubUsername)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    HStack {
                        Image(systemName: "key")
                            .foregroundStyle(.secondary)
                        if showToken {
                            TextField("Personal Access Token", text: $githubToken)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("Personal Access Token", text: $githubToken)
                        }
                        Button(action: { showToken.toggle() }) {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(action: { showTokenHelp = true }) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            Text("How to get a Personal Access Token")
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("GitHub Account")
                } footer: {
                    HStack(spacing: 4) {
                        Image(systemName: githubToken.isEmpty ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(githubToken.isEmpty ? .red : .green)
                        Text(githubToken.isEmpty ? "Token required for Git operations" : "Token configured")
                    }
                    .font(.caption)
                }

                // Project Settings
                Section {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        TextField("Default Project Name", text: $defaultProject)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Defaults")
                } footer: {
                    Text("Default project folder for saving generated code")
                }

                // Storage Info
                Section {
                    StorageRow(title: "Models", path: ModelManager.shared.modelsDirectory.path)
                    StorageRow(title: "Projects", path: FileService.shared.projectsRoot.path)
                } header: {
                    Text("Storage")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Engine")
                        Spacer()
                        Text("llama.cpp")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/ggml-org/llama.cpp")!) {
                        HStack {
                            Text("llama.cpp on GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showTokenHelp) {
                tokenHelpSheet
            }
        }
    }

    private var tokenHelpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Creating a GitHub Personal Access Token")
                        .font(.title3.bold())

                    Group {
                        step(1, "Go to GitHub.com → Settings")
                        step(2, "Click 'Developer settings' in the left sidebar")
                        step(3, "Click 'Personal access tokens' → 'Tokens (classic)'")
                        step(4, "Click 'Generate new token (classic)'")
                        step(5, "Give it a name like 'LocalCoder'")
                        step(6, "Select scopes: 'repo' (full control of repositories)")
                        step(7, "Click 'Generate token'")
                        step(8, "Copy the token and paste it in Settings")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("⚠️ Important")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                        Text("Keep your token secret! It grants access to your GitHub account. The token is stored securely on your device only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showTokenHelp = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
        }
    }
}

struct StorageRow: View {
    let title: String
    let path: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(directorySize)
                .foregroundStyle(.secondary)
        }
    }

    private var directorySize: String {
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
}
