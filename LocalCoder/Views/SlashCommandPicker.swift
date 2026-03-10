import SwiftUI

/// Available slash commands
enum SlashCommand: String, CaseIterable, Identifiable {
    case new = "new"
    case tools = "tools"
    case model = "model"
    case clear = "clear"
    case help = "help"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .new: return "/new"
        case .tools: return "/tools"
        case .model: return "/model"
        case .clear: return "/clear"
        case .help: return "/help"
        }
    }

    var description: String {
        switch self {
        case .new: return "Start a new conversation"
        case .tools: return "Toggle tools on/off"
        case .model: return "Select or download a model"
        case .clear: return "Clear chat history"
        case .help: return "Show available commands"
        }
    }

    var icon: String {
        switch self {
        case .new: return "plus.message"
        case .tools: return "wrench.and.screwdriver"
        case .model: return "cpu"
        case .clear: return "trash"
        case .help: return "questionmark.circle"
        }
    }

    /// Filter commands by a search string
    static func filtered(by filter: String) -> [SlashCommand] {
        if filter.isEmpty {
            return SlashCommand.allCases
        }
        let lowercased = filter.lowercased()
        return SlashCommand.allCases.filter { cmd in
            cmd.rawValue.lowercased().contains(lowercased)
        }
    }
}

/// A dropdown picker for slash commands
struct SlashCommandPicker: View {
    let filter: String
    let onSelect: (SlashCommand) -> Void
    let onDismiss: () -> Void

    private var filteredCommands: [SlashCommand] {
        SlashCommand.filtered(by: filter)
    }

    var body: some View {
        VStack(spacing: 0) {
            if filteredCommands.isEmpty {
                HStack {
                    Text("No matching commands")
                        .font(LC.caption(12))
                        .foregroundStyle(LC.secondary)
                    Spacer()
                }
                .padding(LC.spacingSM)
            } else {
                ForEach(filteredCommands) { cmd in
                    SlashCommandRow(command: cmd)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(cmd)
                        }
                }
            }
        }
        .background(LC.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: LC.radiusMD))
        .overlay(
            RoundedRectangle(cornerRadius: LC.radiusMD)
                .stroke(LC.border, lineWidth: LC.borderWidth)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

/// A single row in the slash command picker
struct SlashCommandRow: View {
    let command: SlashCommand

    var body: some View {
        HStack(spacing: LC.spacingSM) {
            Image(systemName: command.icon)
                .font(.system(size: 12))
                .foregroundStyle(LC.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(command.displayName)
                    .font(LC.code(13))
                    .foregroundStyle(LC.primary)

                Text(command.description)
                    .font(LC.caption(10))
                    .foregroundStyle(LC.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, LC.spacingSM)
        .padding(.vertical, 8)
        .background(LC.surfaceElevated)
    }
}

/// Tool settings model
struct ToolSetting: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    var isEnabled: Bool
}

/// Interactive menu to toggle tools on/off
struct ToolsMenuView: View {
    @Binding var tools: [ToolSetting]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TOOLS")
                    .font(LC.label(11))
                    .tracking(1.5)
                    .foregroundStyle(LC.secondary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LC.secondary)
                }
            }
            .padding(LC.spacingSM)
            .background(LC.surface)

            Divider().background(LC.border)

            // Tool toggles
            ForEach($tools) { $tool in
                ToolToggleRow(tool: $tool)
                Divider().background(LC.border.opacity(0.5))
            }

            // Footer hint
            HStack {
                Text("Disabled tools won't be used by the model")
                    .font(LC.caption(10))
                    .foregroundStyle(LC.secondary)
                Spacer()
            }
            .padding(LC.spacingSM)
        }
        .background(LC.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: LC.radiusMD))
        .overlay(
            RoundedRectangle(cornerRadius: LC.radiusMD)
                .stroke(LC.border, lineWidth: LC.borderWidth)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

/// A single tool toggle row
struct ToolToggleRow: View {
    @Binding var tool: ToolSetting

    var body: some View {
        HStack(spacing: LC.spacingSM) {
            Image(systemName: tool.icon)
                .font(.system(size: 14))
                .foregroundStyle(tool.isEnabled ? LC.accent : LC.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(LC.body(13))
                    .foregroundStyle(tool.isEnabled ? LC.primary : LC.secondary)

                Text(tool.description)
                    .font(LC.caption(10))
                    .foregroundStyle(LC.secondary)
            }

            Spacer()

            Toggle("", isOn: $tool.isEnabled)
                .labelsHidden()
                .tint(LC.accent)
                .scaleEffect(0.8)
        }
        .padding(.horizontal, LC.spacingSM)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            tool.isEnabled.toggle()
        }
    }
}

/// Interactive menu to select and download models
struct ModelMenuView: View {
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var llmService: LLMService
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("MODELS")
                    .font(LC.label(11))
                    .tracking(1.5)
                    .foregroundStyle(LC.secondary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LC.secondary)
                }
            }
            .padding(LC.spacingSM)
            .background(LC.surface)

            Divider().background(LC.border)

            // Model list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(modelManager.availableModels) { model in
                        ModelMenuRow(
                            model: model,
                            isActive: llmService.isActive(model),
                            isDownloading: modelManager.downloadingModelId == model.id,
                            downloadProgress: modelManager.downloadingModelId == model.id ? modelManager.downloadProgress : 0,
                            onSelect: {
                                Task {
                                    await selectModel(model)
                                }
                            },
                            onDownload: {
                                Task {
                                    await downloadModel(model)
                                }
                            }
                        )
                        Divider().background(LC.border.opacity(0.5))
                    }
                }
            }
            .frame(maxHeight: 300)

            // Footer hint
            HStack {
                if let activeModelName = llmService.activeModelName {
                    Text("Active: \(activeModelName)")
                        .font(LC.caption(10))
                        .foregroundStyle(LC.accent)
                } else {
                    Text("No model loaded")
                        .font(LC.caption(10))
                        .foregroundStyle(LC.secondary)
                }
                Spacer()
            }
            .padding(LC.spacingSM)
        }
        .background(LC.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: LC.radiusMD))
        .overlay(
            RoundedRectangle(cornerRadius: LC.radiusMD)
                .stroke(LC.border, lineWidth: LC.borderWidth)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    private func selectModel(_ model: ModelInfo) async {
        guard model.isDownloaded else { return }
        do {
            try await llmService.loadModel(model)
            onDismiss()
        } catch {
            // Error is shown via llmService.lastErrorMessage
        }
    }

    private func downloadModel(_ model: ModelInfo) async {
        do {
            try await modelManager.downloadModel(model)
        } catch {
            // Error handling could be added here
        }
    }
}

/// A single model row in the model menu
struct ModelMenuRow: View {
    let model: ModelInfo
    let isActive: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onSelect: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: LC.spacingSM) {
            // Status icon
            Group {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LC.accent)
                } else if model.isDownloaded {
                    Image(systemName: "circle")
                        .foregroundStyle(LC.secondary)
                } else if isDownloading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(LC.accent)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(LC.secondary)
                }
            }
            .font(.system(size: 14))
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(LC.body(13))
                        .foregroundStyle(isActive ? LC.accent : (model.isDownloaded ? LC.primary : LC.secondary))
                        .lineLimit(1)

                    Text(model.size)
                        .font(LC.label(8))
                        .tracking(0.5)
                        .foregroundStyle(LC.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(LC.surface)
                        .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                }

                Text(model.description)
                    .font(LC.caption(10))
                    .foregroundStyle(LC.secondary)
                    .lineLimit(2)

                // Download progress bar
                if isDownloading {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(LC.border)
                                .frame(height: 3)

                            Rectangle()
                                .fill(LC.accent)
                                .frame(width: geometry.size.width * downloadProgress, height: 3)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    }
                    .frame(height: 3)
                    .padding(.top, 4)
                }
            }

            Spacer()

            // Action button
            if !isActive {
                if model.isDownloaded {
                    Button(action: onSelect) {
                        Text("LOAD")
                            .font(LC.label(9))
                            .tracking(1)
                            .foregroundStyle(LC.accent)
                    }
                } else if !isDownloading {
                    Button(action: onDownload) {
                        Text("GET")
                            .font(LC.label(9))
                            .tracking(1)
                            .foregroundStyle(LC.accent)
                    }
                }
            }
        }
        .padding(.horizontal, LC.spacingSM)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded && !isActive {
                onSelect()
            } else if !model.isDownloaded && !isDownloading {
                onDownload()
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SlashCommandPicker(
            filter: "",
            onSelect: { _ in },
            onDismiss: {}
        )
        .padding()

        ToolsMenuView(
            tools: .constant([
                ToolSetting(id: "read", name: "read", description: "Read file contents", icon: "doc.text", isEnabled: true),
                ToolSetting(id: "write", name: "write", description: "Create or overwrite files", icon: "square.and.pencil", isEnabled: true),
                ToolSetting(id: "edit", name: "edit", description: "Surgical find-and-replace", icon: "pencil", isEnabled: true),
                ToolSetting(id: "bash", name: "bash", description: "Execute filesystem commands", icon: "terminal", isEnabled: false),
            ]),
            onDismiss: {}
        )
        .padding()
    }
    .background(LC.surface)
}
