import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

struct CodeBlock: Identifiable {
    let id = UUID()
    let language: String
    let code: String
    let filename: String?
}

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileItem]?

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.path == rhs.path
    }
}

struct GitStatus {
    var branch: String = "main"
    var staged: [String] = []
    var modified: [String] = []
    var untracked: [String] = []
    var isRepo: Bool = false
}

struct ModelInfo: Identifiable, Codable {
    let id: String
    let name: String
    let filename: String
    let url: String
    let size: String
    let description: String
    var isDownloaded: Bool = false
}
