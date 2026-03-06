import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

@MainActor
final class DebugConsole: ObservableObject {
    static let shared = DebugConsole()

    @Published private(set) var entries: [DebugLogEntry] = []

    private let maxEntries = 300
    private let fileURL: URL
    #if os(iOS)
    private var memoryWarningObserver: NSObjectProtocol?
    #endif

    private init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let debugDirectory = documentsURL.appendingPathComponent("Debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
        fileURL = debugDirectory.appendingPathComponent("debug-log.json")

        loadEntriesFromDisk()
        log("App launched", category: .app)

        #if os(iOS)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.log("Received iOS memory warning", category: .app, level: .warning)
        }
        #endif
    }

    deinit {
        #if os(iOS)
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
        #endif
    }

    func log(
        _ message: String,
        category: DebugLogCategory = .app,
        level: DebugLogLevel = .info,
        details: String? = nil
    ) {
        let entry = DebugLogEntry(
            level: level,
            category: category,
            message: message,
            details: details
        )

        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        persistEntries()
    }

    func clear() {
        entries.removeAll()
        persistEntries()
        log("Debug log cleared", category: .app, level: .debug)
    }

    func exportText() -> String {
        entries.map(\.formattedLine).joined(separator: "\n\n")
    }

    var latestEntry: DebugLogEntry? {
        entries.last
    }

    var errorCount: Int {
        entries.filter { $0.level == .error }.count
    }

    private func loadEntriesFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([DebugLogEntry].self, from: data) {
            entries = Array(decoded.suffix(maxEntries))
        }
    }

    private func persistEntries() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct DebugLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: DebugLogLevel
    let category: DebugLogCategory
    let message: String
    let details: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: DebugLogLevel,
        category: DebugLogCategory,
        message: String,
        details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.details = details
    }

    var timestampLabel: String {
        timestamp.debugConsoleTimestamp
    }

    var formattedLine: String {
        let detailsSuffix = details?.isEmpty == false ? "\n\(details!)" : ""
        return "[\(timestampLabel)] [\(level.rawValue.uppercased())] [\(category.rawValue.uppercased())] \(message)\(detailsSuffix)"
    }
}

enum DebugLogLevel: String, Codable, CaseIterable {
    case debug
    case info
    case warning
    case error
}

enum DebugLogCategory: String, Codable, CaseIterable {
    case app
    case chat
    case llm
    case model
    case tools
}

private extension Date {
    var debugConsoleTimestamp: String {
        DebugConsoleDateFormatter.shared.string(from: self)
    }
}

private enum DebugConsoleDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
