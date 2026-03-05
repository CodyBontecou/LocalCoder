import Foundation

/// Downloads and manages GGUF model files
@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var availableModels: [ModelInfo] = []
    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false
    @Published var downloadingModelId: String?

    private var downloadTask: URLSessionDownloadTask?

    var modelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models")
    }

    private init() {
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        loadAvailableModels()
    }

    func loadAvailableModels() {
        // Curated list of coding-optimized models that work well on iPhone
        var models: [ModelInfo] = [
            ModelInfo(
                id: "qwen25-coder-1.5b-q4",
                name: "Qwen 2.5 Coder 1.5B (Q4_K_M)",
                filename: "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
                url: "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
                size: "1.0 GB",
                description: "Fast, great for quick code snippets. Runs well on all iPhones."
            ),
            ModelInfo(
                id: "qwen25-coder-3b-q4",
                name: "Qwen 2.5 Coder 3B (Q4_K_M)",
                filename: "qwen2.5-coder-3b-instruct-q4_k_m.gguf",
                url: "https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf",
                size: "2.0 GB",
                description: "Best balance of quality and speed. Recommended for iPhone 15+."
            ),
            ModelInfo(
                id: "qwen25-coder-7b-q4",
                name: "Qwen 2.5 Coder 7B (Q4_K_M)",
                filename: "qwen2.5-coder-7b-instruct-q4_k_m.gguf",
                url: "https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf",
                size: "4.7 GB",
                description: "Highest quality code generation. Requires iPhone 15 Pro+ (8GB RAM)."
            ),
            ModelInfo(
                id: "deepseek-coder-1.3b-q4",
                name: "DeepSeek Coder 1.3B (Q4_K_M)",
                filename: "deepseek-coder-1.3b-instruct-q4_k_m.gguf",
                url: "https://huggingface.co/TheBloke/deepseek-coder-1.3b-instruct-GGUF/resolve/main/deepseek-coder-1.3b-instruct.Q4_K_M.gguf",
                size: "0.8 GB",
                description: "Tiny and fast. Good for simple code tasks on any device."
            ),
            ModelInfo(
                id: "codellama-7b-q4",
                name: "CodeLlama 7B Instruct (Q4_K_M)",
                filename: "codellama-7b-instruct.Q4_K_M.gguf",
                url: "https://huggingface.co/TheBloke/CodeLlama-7B-Instruct-GGUF/resolve/main/codellama-7b-instruct.Q4_K_M.gguf",
                size: "4.1 GB",
                description: "Meta's code model. Strong at Python, C++, Java. Needs 8GB RAM."
            ),
        ]

        // Check which are already downloaded
        for i in models.indices {
            let path = modelsDirectory.appendingPathComponent(models[i].filename).path
            models[i].isDownloaded = FileManager.default.fileExists(atPath: path)
        }

        // Also scan for any additional GGUF files in the models directory
        if let files = try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path) {
            for file in files where file.hasSuffix(".gguf") {
                if !models.contains(where: { $0.filename == file }) {
                    models.append(ModelInfo(
                        id: file,
                        name: file.replacingOccurrences(of: ".gguf", with: ""),
                        filename: file,
                        url: "",
                        size: fileSizeString(modelsDirectory.appendingPathComponent(file)),
                        description: "Manually added model",
                        isDownloaded: true
                    ))
                }
            }
        }

        availableModels = models
    }

    func modelPath(for model: ModelInfo) -> String {
        modelsDirectory.appendingPathComponent(model.filename).path
    }

    func downloadModel(_ model: ModelInfo) async throws {
        guard let url = URL(string: model.url) else { throw ModelError.invalidURL }

        isDownloading = true
        downloadingModelId = model.id
        downloadProgress = 0

        defer {
            isDownloading = false
            downloadingModelId = nil
        }

        let destination = modelsDirectory.appendingPathComponent(model.filename)

        // Use URLSession delegate for progress tracking
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelError.downloadFailed
        }

        let totalBytes = response.expectedContentLength
        var downloadedBytes: Int64 = 0
        var data = Data()
        data.reserveCapacity(totalBytes > 0 ? Int(totalBytes) : 1_000_000_000)

        for try await byte in asyncBytes {
            data.append(byte)
            downloadedBytes += 1

            if downloadedBytes % (1024 * 1024) == 0 && totalBytes > 0 {
                downloadProgress = Double(downloadedBytes) / Double(totalBytes)
            }
        }

        try data.write(to: destination)
        downloadProgress = 1.0

        // Update model list
        loadAvailableModels()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        isDownloading = false
        downloadingModelId = nil
        downloadProgress = 0
    }

    func deleteModel(_ model: ModelInfo) throws {
        let path = modelsDirectory.appendingPathComponent(model.filename)
        try FileManager.default.removeItem(at: path)
        loadAvailableModels()
    }

    func downloadedModels() -> [ModelInfo] {
        availableModels.filter(\.isDownloaded)
    }

    private func fileSizeString(_ url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return "Unknown" }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

enum ModelError: LocalizedError {
    case invalidURL
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid model download URL"
        case .downloadFailed: return "Model download failed"
        }
    }
}
