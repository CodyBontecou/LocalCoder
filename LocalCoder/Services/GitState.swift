import Foundation

struct GitState: Codable, Equatable {
    var commitSHA: String
    var treeSHA: String
    var branch: String
    var blobSHAs: [String: String]  // relative path → blob SHA
    var lastSyncDate: Date

    static let empty = GitState(
        commitSHA: "",
        treeSHA: "",
        branch: "main",
        blobSHAs: [:],
        lastSyncDate: .distantPast
    )
}
