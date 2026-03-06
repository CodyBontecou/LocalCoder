import Foundation
import Hub
import MLXLLM
import MLXLMCommon

/// Downloads and manages MLX model folders from Hugging Face.
@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var availableModels: [ModelInfo] = []
    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false
    @Published var downloadingModelId: String?

    let hub: HubApi

    private let downloadedPathsKey = "downloaded_mlx_model_paths"

    var modelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models")
    }

    private init() {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        hub = HubApi(downloadBase: root)
        loadAvailableModels()
    }

    func loadAvailableModels() {
        var models = curatedModels()
        let downloadedMap = storedDownloadedPaths()

        for index in models.indices {
            if let storedPath = downloadedMap[models[index].id],
               resolveStoredPath(storedPath) != nil {
                models[index].isDownloaded = true
            }
        }

        // Scan for local MLX model folders manually added to Documents/Models
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in contents {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDir, isMLXModelDirectory(url) else { continue }

                if !models.contains(where: { $0.localPath == url.path }) {
                    models.append(
                        ModelInfo(
                            id: url.lastPathComponent,
                            name: url.lastPathComponent,
                            repositoryID: nil,
                            localPath: url.path,
                            size: fileSizeString(url),
                            description: "Local MLX model folder",
                            isDownloaded: true
                        )
                    )
                }
            }
        }

        availableModels = models.sorted { lhs, rhs in
            if lhs.isDownloaded != rhs.isDownloaded {
                return lhs.isDownloaded && !rhs.isDownloaded
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func downloadModel(_ model: ModelInfo) async throws {
        guard let repositoryID = model.repositoryID else {
            throw ModelError.invalidModelIdentifier
        }

        isDownloading = true
        downloadingModelId = model.id
        downloadProgress = 0

        defer {
            isDownloading = false
            downloadingModelId = nil
        }

        let configuration = LLMModelFactory.shared.configuration(id: repositoryID)
        let downloadedURL = try await MLXLMCommon.downloadModel(
            hub: hub,
            configuration: configuration,
            progressHandler: { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }
        )

        var map = storedDownloadedPaths()
        map[model.id] = relativePath(from: downloadedURL.path)
        saveDownloadedPaths(map)
        downloadProgress = 1.0
        loadAvailableModels()
    }

    func cancelDownload() {
        // Hub download cancellation is not currently wired through this view model.
        isDownloading = false
        downloadingModelId = nil
        downloadProgress = 0
    }

    func deleteModel(_ model: ModelInfo) throws {
        if let localPath = model.localPath {
            try FileManager.default.removeItem(atPath: localPath)
        } else {
            var map = storedDownloadedPaths()
            if let storedPath = map[model.id],
               let resolvedPath = resolveStoredPath(storedPath),
               FileManager.default.fileExists(atPath: resolvedPath) {
                try FileManager.default.removeItem(atPath: resolvedPath)
            }
            map.removeValue(forKey: model.id)
            saveDownloadedPaths(map)
        }

        loadAvailableModels()
    }

    func downloadedModels() -> [ModelInfo] {
        availableModels.filter(\.isDownloaded)
    }

    func localURL(for model: ModelInfo) -> URL? {
        if let localPath = model.localPath {
            return URL(fileURLWithPath: localPath)
        }
        if let storedPath = storedDownloadedPaths()[model.id],
           let resolvedPath = resolveStoredPath(storedPath) {
            return URL(fileURLWithPath: resolvedPath)
        }
        return nil
    }

    // MARK: - Private

    private func curatedModels() -> [ModelInfo] {
        [
            ModelInfo(
                id: "qwen25-coder-1.5b-instruct-4bit",
                name: "Qwen 2.5 Coder 1.5B Instruct 4-bit",
                repositoryID: "mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit",
                localPath: nil,
                size: "~1 GB",
                description: "Compact coding-focused model optimized for code completion and generation on Apple Silicon. Recommended."
            ),
            ModelInfo(
                id: "qwen3-1.7b-4bit",
                name: "Qwen 3 1.7B 4-bit",
                repositoryID: "mlx-community/Qwen3-1.7B-4bit",
                localPath: nil,
                size: "~1.1 GB",
                description: "Latest Qwen 3 model with strong reasoning capabilities and fast inference."
            ),
            ModelInfo(
                id: "smollm3-3b-4bit",
                name: "SmolLM3 3B 4-bit",
                repositoryID: "mlx-community/SmolLM3-3B-4bit",
                localPath: nil,
                size: "~1.8 GB",
                description: "Efficient 3B parameter model with good coding and reasoning abilities."
            ),
            // Note: Gemma 3 models have a known bug with sliding window attention on longer prompts.
            // Uncomment when upstream fix is available in mlx-swift-lm.
            // ModelInfo(
            //     id: "gemma3n-e2b-it-4bit",
            //     name: "Gemma 3n E2B Instruct 4-bit",
            //     repositoryID: "mlx-community/gemma-3n-E2B-it-lm-4bit",
            //     localPath: nil,
            //     size: "~1.5 GB",
            //     description: "Lightweight Gemma 3n with ~2B effective parameters for fast local inference."
            // ),
            // ModelInfo(
            //     id: "gemma3-1b-it-qat-4bit",
            //     name: "Gemma 3 1B Instruct QAT 4-bit",
            //     repositoryID: "mlx-community/gemma-3-1b-it-qat-4bit",
            //     localPath: nil,
            //     size: "~700 MB",
            //     description: "Ultra-compact Gemma 3 instruction model using quantization-aware training for quality at small size."
            // ),
        ]
    }

    /// Convert an absolute path to a relative path (relative to modelsDirectory) for stable storage.
    /// On iOS the app container UUID can change between launches, so absolute paths become stale.
    private func relativePath(from absolutePath: String) -> String {
        let base = modelsDirectory.path
        if absolutePath.hasPrefix(base) {
            var relative = String(absolutePath.dropFirst(base.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            return relative
        }
        return absolutePath
    }

    /// Resolve a stored path (relative or legacy absolute) to a valid current absolute path.
    /// Returns `nil` if the model directory no longer exists at either location.
    private func resolveStoredPath(_ storedPath: String) -> String? {
        // Try as relative to the current modelsDirectory first (preferred)
        let resolved = modelsDirectory.appendingPathComponent(storedPath).path
        if modelDirectoryExists(at: resolved) {
            return resolved
        }
        // Fall back to treating it as an absolute path (legacy entries)
        if modelDirectoryExists(at: storedPath) {
            return storedPath
        }
        return nil
    }

    private func storedDownloadedPaths() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: downloadedPathsKey) as? [String: String] ?? [:]
    }

    private func saveDownloadedPaths(_ value: [String: String]) {
        UserDefaults.standard.set(value, forKey: downloadedPathsKey)
    }

    private func modelDirectoryExists(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return isMLXModelDirectory(url)
    }

    private func isMLXModelDirectory(_ url: URL) -> Bool {
        let configURL = url.appendingPathComponent("config.json")
        let tokenizerURL = url.appendingPathComponent("tokenizer.json")
        let generationURL = url.appendingPathComponent("generation_config.json")

        let hasConfig = FileManager.default.fileExists(atPath: configURL.path)
        let hasTokenizer = FileManager.default.fileExists(atPath: tokenizerURL.path)
            || FileManager.default.fileExists(atPath: generationURL.path)
        let hasSafeTensors = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?
            .contains(where: { $0.hasSuffix(".safetensors") }) ?? false

        return hasConfig && hasTokenizer && hasSafeTensors
    }

    private func fileSizeString(_ url: URL) -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "Unknown"
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

enum ModelError: LocalizedError {
    case invalidModelIdentifier

    var errorDescription: String? {
        switch self {
        case .invalidModelIdentifier:
            return "This model is missing its Hugging Face identifier."
        }
    }
}
