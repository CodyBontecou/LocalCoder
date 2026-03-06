import Foundation

/// Persists conversations as individual JSON files in the app's documents directory.
@MainActor
final class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    /// Lightweight metadata for the conversation list (avoids loading all messages).
    struct ConversationSummary: Identifiable {
        let id: UUID
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let messageCount: Int
    }

    @Published var summaries: [ConversationSummary] = []

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        ensureDirectory()
        loadSummaries()
    }

    // MARK: - Directory

    private var conversationsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Conversations", isDirectory: true)
    }

    private func ensureDirectory() {
        let dir = conversationsDirectory
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func fileURL(for id: UUID) -> URL {
        conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Save

    func save(_ conversation: Conversation) {
        do {
            let data = try encoder.encode(conversation)
            try data.write(to: fileURL(for: conversation.id), options: .atomic)
            loadSummaries()
        } catch {
            print("[ConversationStore] Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Load

    func load(id: UUID) -> Conversation? {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Conversation.self, from: data)
    }

    // MARK: - Delete

    func delete(id: UUID) {
        let url = fileURL(for: id)
        try? fileManager.removeItem(at: url)
        loadSummaries()
    }

    // MARK: - Summaries

    func loadSummaries() {
        ensureDirectory()

        guard let files = try? fileManager.contentsOfDirectory(
            at: conversationsDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            summaries = []
            return
        }

        var results: [ConversationSummary] = []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let conversation = try? decoder.decode(Conversation.self, from: data) else {
                continue
            }

            results.append(ConversationSummary(
                id: conversation.id,
                title: conversation.title,
                createdAt: conversation.createdAt,
                updatedAt: conversation.updatedAt,
                messageCount: conversation.messages.count
            ))
        }

        // Most recent first
        summaries = results.sorted { $0.updatedAt > $1.updatedAt }
    }
}
