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
    private let customModelsKey = "custom_mlx_models"

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

        // Load custom models from UserDefaults
        let customModels = loadCustomModels()
        models.append(contentsOf: customModels)

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

    // MARK: - Custom Models

    /// Add a custom model from a HuggingFace URL or repository ID.
    /// Accepts URLs like:
    /// - https://huggingface.co/mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit
    /// - mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit
    func addCustomModel(from input: String) throws -> ModelInfo {
        let repositoryID = try parseRepositoryID(from: input)

        // Check if model already exists
        if availableModels.contains(where: { $0.repositoryID == repositoryID }) {
            throw CustomModelError.modelAlreadyExists
        }

        // Create a user-friendly name from the repo ID
        let name = repositoryID.components(separatedBy: "/").last ?? repositoryID

        let model = ModelInfo(
            id: "custom-\(repositoryID.replacingOccurrences(of: "/", with: "-"))",
            name: name,
            repositoryID: repositoryID,
            localPath: nil,
            size: "Unknown",
            description: "Custom model from \(repositoryID)",
            isDownloaded: false,
            isCustom: true
        )

        // Persist the custom model
        var customModels = loadCustomModels()
        customModels.append(model)
        saveCustomModels(customModels)

        loadAvailableModels()
        return model
    }

    /// Remove a custom model (only works for user-added models).
    func removeCustomModel(_ model: ModelInfo) throws {
        guard model.isCustom else {
            throw CustomModelError.cannotRemoveCuratedModel
        }

        // Delete from disk if downloaded
        if model.isDownloaded {
            try? deleteModel(model)
        }

        // Remove from custom models list
        var customModels = loadCustomModels()
        customModels.removeAll { $0.id == model.id }
        saveCustomModels(customModels)

        loadAvailableModels()
    }

    /// Parse a HuggingFace URL or repository ID string into a valid repository ID.
    private func parseRepositoryID(from input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle full HuggingFace URLs
        // https://huggingface.co/mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit
        if let url = URL(string: trimmed), url.host?.contains("huggingface") == true {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            guard pathComponents.count >= 2 else {
                throw CustomModelError.invalidURL
            }
            return "\(pathComponents[0])/\(pathComponents[1])"
        }

        // Handle direct repository ID format: org/model-name
        if trimmed.contains("/") && !trimmed.contains("://") {
            let parts = trimmed.components(separatedBy: "/")
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw CustomModelError.invalidRepositoryID
            }
            return trimmed
        }

        throw CustomModelError.invalidInput
    }

    private func loadCustomModels() -> [ModelInfo] {
        guard let data = UserDefaults.standard.data(forKey: customModelsKey),
              let models = try? JSONDecoder().decode([ModelInfo].self, from: data) else {
            return []
        }
        return models
    }

    private func saveCustomModels(_ models: [ModelInfo]) {
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: customModelsKey)
        }
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
            // MARK: - Top Coding Models (Q1 2026)
            ModelInfo(
                id: "qwen3-coder-next-4bit",
                name: "Qwen3 Coder Next 4-bit ⭐",
                repositoryID: "mlx-community/Qwen3-Coder-Next-4bit",
                localPath: nil,
                size: "~14 GB",
                description: "State-of-the-art coding model (Feb 2026). 24B params with MoE (~3B active). Best coding performance on Apple Silicon."
            ),
            ModelInfo(
                id: "qwen3-coder-30b-a3b-4bit",
                name: "Qwen3 Coder 30B-A3B 4-bit",
                repositoryID: "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit",
                localPath: nil,
                size: "~18 GB",
                description: "Latest Qwen3 coder with 30B params (3B active MoE). Excellent for complex coding tasks."
            ),
            ModelInfo(
                id: "deepseek-coder-v2-lite-4bit",
                name: "DeepSeek Coder V2 Lite 4-bit",
                repositoryID: "mlx-community/DeepSeek-Coder-V2-Lite-Instruct-4bit",
                localPath: nil,
                size: "~9 GB",
                description: "Efficient MoE coding model with 16B params (~2B active). Strong code generation."
            ),
            
            // MARK: - Qwen 3.5 Series (March 2026)
            ModelInfo(
                id: "qwen35-9b-4bit",
                name: "Qwen 3.5 9B 4-bit",
                repositoryID: "mlx-community/Qwen3.5-9B-4bit",
                localPath: nil,
                size: "~5.5 GB",
                description: "Latest Qwen 3.5 (March 2026) with excellent reasoning and coding. Best quality in the series."
            ),
            ModelInfo(
                id: "qwen35-4b-4bit",
                name: "Qwen 3.5 4B 4-bit",
                repositoryID: "mlx-community/Qwen3.5-4B-4bit",
                localPath: nil,
                size: "~2.5 GB",
                description: "Qwen 3.5 with 4B parameters. Great balance of quality and speed for coding."
            ),
            ModelInfo(
                id: "qwen35-2b-4bit",
                name: "Qwen 3.5 2B 4-bit",
                repositoryID: "mlx-community/Qwen3.5-2B-4bit",
                localPath: nil,
                size: "~1.2 GB",
                description: "Qwen 3.5 with 2B parameters, balanced performance and efficiency on Apple Silicon."
            ),
            ModelInfo(
                id: "qwen35-0.8b-4bit",
                name: "Qwen 3.5 0.8B 4-bit",
                repositoryID: "mlx-community/Qwen3.5-0.8B-4bit",
                localPath: nil,
                size: "~0.5 GB",
                description: "Ultra-compact Qwen 3.5 with 0.8B parameters. Fast inference, great for iPhone."
            ),
            
            // MARK: - Compact Coding Models
            ModelInfo(
                id: "qwen25-coder-1.5b-instruct-4bit",
                name: "Qwen 2.5 Coder 1.5B Instruct 4-bit",
                repositoryID: "mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit",
                localPath: nil,
                size: "~1 GB",
                description: "Compact coding-focused model optimized for code completion and generation on Apple Silicon."
            ),
            ModelInfo(
                id: "qwen25-coder-7b-instruct-4bit",
                name: "Qwen 2.5 Coder 7B Instruct 4-bit",
                repositoryID: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
                localPath: nil,
                size: "~4.5 GB",
                description: "Qwen 2.5 Coder with 7B parameters. Strong coding performance, good for Mac."
            ),
            ModelInfo(
                id: "smollm3-3b-4bit",
                name: "SmolLM3 3B 4-bit",
                repositoryID: "mlx-community/SmolLM3-3B-4bit",
                localPath: nil,
                size: "~1.8 GB",
                description: "Efficient 3B parameter model with good coding and reasoning abilities."
            ),
            ModelInfo(
                id: "qwen3-1.7b-4bit",
                name: "Qwen 3 1.7B 4-bit",
                repositoryID: "mlx-community/Qwen3-1.7B-4bit",
                localPath: nil,
                size: "~1.1 GB",
                description: "Qwen 3 model with strong reasoning capabilities and fast inference."
            ),
            // MARK: - Gemma Models
            // Note: Gemma 3n models may have sliding window attention issues in very long conversations.
            ModelInfo(
                id: "gemma3-1b-it-qat-4bit",
                name: "Gemma 3 1B Instruct QAT 4-bit",
                repositoryID: "mlx-community/gemma-3-1b-it-qat-4bit",
                localPath: nil,
                size: "~700 MB",
                description: "Ultra-compact Gemma 3 instruction model using quantization-aware training for quality at small size."
            ),
            ModelInfo(
                id: "gemma3n-e2b-it-lm-4bit",
                name: "Gemma 3n E2B Instruct 4-bit",
                repositoryID: "mlx-community/gemma-3n-E2B-it-lm-4bit",
                localPath: nil,
                size: "~1.5 GB",
                description: "Lightweight Gemma 3n with ~2B effective parameters for fast local inference."
            ),
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

enum CustomModelError: LocalizedError {
    case invalidURL
    case invalidRepositoryID
    case invalidInput
    case modelAlreadyExists
    case cannotRemoveCuratedModel

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid HuggingFace URL. Expected format: https://huggingface.co/org/model-name"
        case .invalidRepositoryID:
            return "Invalid repository ID. Expected format: org/model-name"
        case .invalidInput:
            return "Please enter a HuggingFace URL or repository ID (e.g., mlx-community/model-name)"
        case .modelAlreadyExists:
            return "This model is already in your list."
        case .cannotRemoveCuratedModel:
            return "Cannot remove built-in models. You can only remove custom models you've added."
        }
    }
}
