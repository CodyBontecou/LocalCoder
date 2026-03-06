import SwiftUI

struct ModelManagerView: View {
    @EnvironmentObject var llmService: LLMService
    @EnvironmentObject var modelManager: ModelManager
    @State private var showDeleteConfirm = false
    @State private var modelToDelete: ModelInfo?
    @State private var loadErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: LC.spacingLG) {
                // Status card
                statusCard

                // Models list
                modelsSection

                // Manual import
                importSection
            }
            .padding(LC.spacingMD)
        }
        .background(LC.surface)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("MODELS")
                    .font(LC.label(12))
                    .tracking(2)
                    .foregroundStyle(LC.primary)
            }
        }
        .toolbarBackground(LC.surfaceElevated, for: .navigationBar)
        .refreshable {
            modelManager.loadAvailableModels()
        }
        .alert("Delete Model?", isPresented: $showDeleteConfirm, presenting: modelToDelete) { model in
            Button("Delete", role: .destructive) {
                try? modelManager.deleteModel(model)
            }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text("Remove \(model.name) from device.")
        }
        .alert(
            "Load Error",
            isPresented: Binding(
                get: { loadErrorMessage != nil },
                set: { if !$0 { loadErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loadErrorMessage ?? "Unknown error")
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: LC.spacingMD) {
            VStack(alignment: .leading, spacing: LC.spacingXS) {
                Text("STATUS")
                    .font(LC.label(9))
                    .tracking(1.5)
                    .foregroundStyle(LC.secondary)

                Text(llmService.isModelLoaded ? "ACTIVE" : "IDLE")
                    .font(LC.heading(20))
                    .foregroundStyle(LC.primary)

                Text(statusSubtitle)
                    .font(LC.caption(11))
                    .foregroundStyle(LC.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(spacing: LC.spacingSM) {
                LCStatusDot(isActive: llmService.isModelLoaded)

                if llmService.isModelLoaded {
                    Button(action: { llmService.unloadModel() }) {
                        Text("UNLOAD")
                            .font(LC.label(8))
                            .tracking(1)
                            .foregroundStyle(LC.destructive)
                    }
                }
            }
        }
        .padding(LC.spacingMD)
        .lcCard()
    }

    private var statusSubtitle: String {
        if let activeModelName = llmService.activeModelName {
            return activeModelName
        }
        if let lastErrorMessage = llmService.lastErrorMessage, !lastErrorMessage.isEmpty {
            return lastErrorMessage
        }
        if !llmService.loadingProgress.isEmpty {
            return llmService.loadingProgress
        }
        return "Load a model below"
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: LC.spacingSM) {
            Text("AVAILABLE")
                .font(LC.label(10))
                .tracking(2)
                .foregroundStyle(LC.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(modelManager.availableModels.enumerated()), id: \.element.id) { index, model in
                    modelRow(for: model)

                    if index < modelManager.availableModels.count - 1 {
                        Rectangle().fill(LC.border).frame(height: LC.borderWidth)
                    }
                }
            }
            .lcCard()

            Text("Large models may exceed device memory.")
                .font(LC.caption(10))
                .foregroundStyle(LC.secondary)
                .padding(.leading, 2)
        }
    }

    @ViewBuilder
    private func modelRow(for model: ModelInfo) -> some View {
        VStack(alignment: .leading, spacing: LC.spacingSM) {
            HStack(alignment: .top, spacing: LC.spacingMD - 4) {
                VStack(alignment: .leading, spacing: LC.spacingXS) {
                    Text(model.name)
                        .font(LC.body(13))
                        .foregroundStyle(LC.primary)

                    Text(model.description)
                        .font(LC.caption(11))
                        .foregroundStyle(LC.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: LC.spacingXS) {
                    Text(model.size)
                        .font(LC.label(9))
                        .tracking(0.5)
                        .foregroundStyle(LC.primary)
                        .padding(.horizontal, LC.spacingSM)
                        .padding(.vertical, 3)
                        .background(LC.border.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))

                    if model.isDownloaded {
                        Text("INSTALLED")
                            .font(LC.label(8))
                            .tracking(1)
                            .foregroundStyle(LC.accent)
                    }

                    if llmService.isActive(model) {
                        Text("LOADED")
                            .font(LC.label(8))
                            .tracking(1)
                            .foregroundStyle(LC.accent)
                    }
                }
            }

            actionRow(for: model)
        }
        .padding(LC.spacingMD)
    }

    @ViewBuilder
    private func actionRow(for model: ModelInfo) -> some View {
        if modelManager.isDownloading && modelManager.downloadingModelId == model.id {
            VStack(spacing: LC.spacingXS) {
                ProgressView(value: modelManager.downloadProgress)
                    .tint(LC.accent)

                HStack {
                    Text("\(Int(modelManager.downloadProgress * 100))%")
                        .font(LC.label(10))
                        .foregroundStyle(LC.primary)
                    Spacer()
                    Button(action: { modelManager.cancelDownload() }) {
                        Text("CANCEL")
                            .font(LC.label(9))
                            .tracking(1)
                            .foregroundStyle(LC.destructive)
                    }
                }
            }
        } else if model.isDownloaded {
            HStack(spacing: LC.spacingSM) {
                if llmService.isActive(model) {
                    LCPillButton(title: "Unload", icon: nil, style: .destructive) {
                        llmService.unloadModel()
                    }
                } else {
                    LCPillButton(title: "Load", icon: nil, style: .primary) {
                        Task {
                            do {
                                try await llmService.loadModel(model)
                            } catch {
                                loadErrorMessage = llmService.lastErrorMessage ?? error.localizedDescription
                            }
                        }
                    }
                }

                Spacer()

                Button(action: {
                    modelToDelete = model
                    showDeleteConfirm = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(LC.secondary)
                }
            }
        } else {
            Button(action: {
                Task { try? await modelManager.downloadModel(model) }
            }) {
                HStack(spacing: LC.spacingSM) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text("DOWNLOAD")
                        .font(LC.label(10))
                        .tracking(1)
                }
                .foregroundStyle(LC.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LC.spacingSM)
                .overlay(
                    RoundedRectangle(cornerRadius: LC.radiusSM)
                        .stroke(LC.accent, lineWidth: LC.borderWidth)
                )
            }
            .disabled(modelManager.isDownloading)
            .opacity(modelManager.isDownloading ? 0.35 : 1)
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        VStack(alignment: .leading, spacing: LC.spacingSM) {
            Text("MANUAL IMPORT")
                .font(LC.label(10))
                .tracking(2)
                .foregroundStyle(LC.secondary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: LC.spacingSM) {
                ForEach(1...4, id: \.self) { num in
                    HStack(alignment: .top, spacing: LC.spacingSM) {
                        Text("\(num)")
                            .font(LC.label(9))
                            .foregroundStyle(LC.accent)
                            .frame(width: 16)

                        Text(importStep(num))
                            .font(LC.caption(11))
                            .foregroundStyle(LC.secondary)
                    }
                }
            }
            .padding(LC.spacingMD)
            .lcCard()
        }
    }

    private func importStep(_ num: Int) -> String {
        switch num {
        case 1: return "Open Files app"
        case 2: return "Navigate to LocalCoder → Models"
        case 3: return "Drop model folder (config.json + .safetensors)"
        case 4: return "Pull to refresh this list"
        default: return ""
        }
    }
}
