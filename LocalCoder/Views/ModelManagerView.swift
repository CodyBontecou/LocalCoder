import SwiftUI

struct ModelManagerView: View {
    @EnvironmentObject var llmService: LLMService
    @EnvironmentObject var modelManager: ModelManager
    @State private var showDeleteConfirm = false
    @State private var modelToDelete: ModelInfo?

    var body: some View {
        List {
            // Currently loaded model
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(llmService.isModelLoaded ? "Model Active" : "No Model Loaded")
                            .font(.headline)
                        Text(llmService.loadingProgress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(llmService.isModelLoaded ? .green : .red)
                        .frame(width: 12, height: 12)
                }

                if llmService.isModelLoaded {
                    Button("Unload Model", role: .destructive) {
                        llmService.unloadModel()
                    }
                }
            } header: {
                Text("Status")
            }

            // Downloaded models
            let downloaded = modelManager.downloadedModels()
            if !downloaded.isEmpty {
                Section {
                    ForEach(downloaded) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.name)
                                    .font(.subheadline.bold())
                                Text(model.size)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Load") {
                                Task {
                                    try? await llmService.loadModel(at: modelManager.modelPath(for: model))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelToDelete = model
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Downloaded Models")
                }
            }

            // Available to download
            Section {
                ForEach(modelManager.availableModels.filter { !$0.isDownloaded }) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.name)
                                    .font(.subheadline.bold())
                                Text(model.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(model.size)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }

                        if modelManager.isDownloading && modelManager.downloadingModelId == model.id {
                            VStack(spacing: 4) {
                                ProgressView(value: modelManager.downloadProgress)
                                    .tint(.green)
                                HStack {
                                    Text("\(Int(modelManager.downloadProgress * 100))%")
                                        .font(.caption.monospacedDigit())
                                    Spacer()
                                    Button("Cancel") {
                                        modelManager.cancelDownload()
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                }
                            }
                        } else {
                            Button(action: {
                                Task {
                                    try? await modelManager.downloadModel(model)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.down.circle")
                                    Text("Download")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                            .disabled(modelManager.isDownloading)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Available Models")
            } footer: {
                Text("Models are downloaded to your device and run entirely offline. Larger models produce better code but need more RAM.")
            }

            // Manual import section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You can also add models manually via the Files app:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Open Files app", systemImage: "1.circle")
                        Label("Navigate to LocalCoder → Models", systemImage: "2.circle")
                        Label("Drop any .gguf file there", systemImage: "3.circle")
                        Label("Pull to refresh this list", systemImage: "4.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Manual Import")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            modelManager.loadAvailableModels()
        }
        .alert("Delete Model?", isPresented: $showDeleteConfirm, presenting: modelToDelete) { model in
            Button("Delete", role: .destructive) {
                try? modelManager.deleteModel(model)
            }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text("This will remove \(model.name) from your device.")
        }
    }
}
