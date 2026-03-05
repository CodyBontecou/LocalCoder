import Foundation
import llama

/// Manages a local llama.cpp model for on-device code generation
@MainActor
final class LLMService: ObservableObject {
    @Published var isModelLoaded = false
    @Published var isGenerating = false
    @Published var loadingProgress: String = ""

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: OpaquePointer?
    private var currentModelPath: String?

    private let maxTokens: Int32 = 2048
    private let contextSize: UInt32 = 4096

    static let shared = LLMService()

    private init() {
        llama_backend_init()
        llama_log_set({ level, text, _ in
            // Suppress verbose logs in production
        }, nil)
    }

    deinit {
        unloadModel()
        llama_backend_free()
    }

    // MARK: - Model Loading

    func loadModel(at path: String) async throws {
        unloadModel()
        loadingProgress = "Loading model..."

        // Load model off main thread
        let (loadedModel, loadedContext) = try await Task.detached(priority: .userInitiated) {
            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = 99 // Use Metal GPU acceleration

            guard let m = llama_model_load_from_file(path, modelParams) else {
                throw LLMError.failedToLoadModel
            }

            var ctxParams = llama_context_default_params()
            ctxParams.n_ctx = 4096
            ctxParams.n_batch = 512
            ctxParams.n_threads = UInt32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))
            ctxParams.n_threads_batch = ctxParams.n_threads

            guard let c = llama_init_from_model(m, ctxParams) else {
                llama_model_free(m)
                throw LLMError.failedToCreateContext
            }

            return (m, c)
        }.value

        self.model = loadedModel
        self.context = loadedContext
        self.currentModelPath = path
        self.isModelLoaded = true
        self.loadingProgress = "Model loaded!"

        // Build sampler
        setupSampler()
    }

    private func setupSampler() {
        let sparams = llama_sampler_chain_default_params()
        sampler = llama_sampler_chain_init(sparams)

        // Temperature + top-p sampling for code generation
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.3))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
    }

    func unloadModel() {
        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        sampler = nil
        context = nil
        model = nil
        isModelLoaded = false
        currentModelPath = nil
    }

    // MARK: - Text Generation

    func generate(messages: [ChatMessage], onToken: @escaping (String) -> Void) async throws {
        guard let model, let context, let sampler else {
            throw LLMError.modelNotLoaded
        }

        isGenerating = true
        defer { isGenerating = false }

        try await Task.detached(priority: .userInitiated) { [maxTokens] in
            // Build prompt using chat template
            let prompt = self.buildPrompt(messages: messages)

            // Tokenize
            let tokens = self.tokenize(model: model, text: prompt, addBos: true)
            guard !tokens.isEmpty else { throw LLMError.tokenizationFailed }

            // Clear KV cache
            llama_kv_cache_clear(context)

            // Create batch and process prompt tokens
            var batch = llama_batch_init(Int32(tokens.count), 0, 1)
            defer { llama_batch_free(batch) }

            for (i, token) in tokens.enumerated() {
                llama_batch_add(&batch, token, Int32(i), [0], i == tokens.count - 1)
            }

            if llama_decode(context, batch) != 0 {
                throw LLMError.decodeFailed
            }

            // Generate tokens
            var generatedCount: Int32 = 0
            var outputTokens: [llama_token] = []

            while generatedCount < maxTokens {
                let newToken = llama_sampler_sample(sampler, context, -1)

                // Check for end of generation
                if llama_vocab_is_eog(llama_model_get_vocab(model), newToken) {
                    break
                }

                outputTokens.append(newToken)
                generatedCount += 1

                // Decode token to string
                let tokenStr = self.tokenToString(model: model, token: newToken)
                await MainActor.run {
                    onToken(tokenStr)
                }

                // Prepare next batch
                var nextBatch = llama_batch_init(1, 0, 1)
                llama_batch_add(&nextBatch, newToken, Int32(tokens.count) + generatedCount - 1, [0], true)

                if llama_decode(context, nextBatch) != 0 {
                    llama_batch_free(nextBatch)
                    throw LLMError.decodeFailed
                }
                llama_batch_free(nextBatch)
            }

            llama_sampler_reset(sampler)
        }.value
    }

    // MARK: - Helpers

    private nonisolated func buildPrompt(messages: [ChatMessage]) -> String {
        // Build a ChatML-style prompt (works with Qwen and most GGUF models)
        var prompt = ""

        // Add system message if not present
        let hasSystem = messages.contains { $0.role == .system }
        if !hasSystem {
            prompt += "<|im_start|>system\nYou are an expert coding assistant. Generate clean, well-documented code. When producing code, wrap it in markdown code blocks with the language specified. If the user asks for a file, include the filename as a comment on the first line.<|im_end|>\n"
        }

        for message in messages {
            switch message.role {
            case .system:
                prompt += "<|im_start|>system\n\(message.content)<|im_end|>\n"
            case .user:
                prompt += "<|im_start|>user\n\(message.content)<|im_end|>\n"
            case .assistant:
                prompt += "<|im_start|>assistant\n\(message.content)<|im_end|>\n"
            }
        }

        prompt += "<|im_start|>assistant\n"
        return prompt
    }

    private nonisolated func tokenize(model: OpaquePointer, text: String, addBos: Bool) -> [llama_token] {
        let utf8 = Array(text.utf8)
        let nTokens = Int32(utf8.count) + (addBos ? 1 : 0)
        var tokens = [llama_token](repeating: 0, count: Int(nTokens))
        let vocab = llama_model_get_vocab(model)
        let count = llama_tokenize(vocab, text, Int32(utf8.count), &tokens, nTokens, addBos, true)
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            let newCount = llama_tokenize(vocab, text, Int32(utf8.count), &tokens, -count, addBos, true)
            return Array(tokens.prefix(Int(newCount)))
        }
        return Array(tokens.prefix(Int(count)))
    }

    private nonisolated func tokenToString(model: OpaquePointer, token: llama_token) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let vocab = llama_model_get_vocab(model)
        let length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        if length > 0 {
            return String(cString: buffer.prefix(Int(length)) + [0])
        }
        return ""
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case failedToLoadModel
    case failedToCreateContext
    case modelNotLoaded
    case tokenizationFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .failedToLoadModel: return "Failed to load the GGUF model file"
        case .failedToCreateContext: return "Failed to create inference context"
        case .modelNotLoaded: return "No model is loaded. Please load a model first."
        case .tokenizationFailed: return "Failed to tokenize input"
        case .decodeFailed: return "Token decode failed during generation"
        }
    }
}
