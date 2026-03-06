import Foundation

/// A single conversation containing its messages and metadata.
struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "New Chat", messages: [ChatMessage] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Derives a title from the first user message, truncated to ~50 chars.
    mutating func deriveTitle() {
        guard let firstUserMessage = messages.first(where: { $0.role == .user }) else { return }
        let raw = firstUserMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.count > 50 {
            title = String(raw.prefix(50)) + "…"
        } else {
            title = raw
        }
    }
}
