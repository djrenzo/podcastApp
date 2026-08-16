import Foundation
import Observation

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let operationName: String
    let requestURL: String
    let requestHeaders: [String: String]
    let requestBody: String
    var statusCode: Int?
    var responseBody: String?
    var errorDescription: String?

    var isSuccess: Bool {
        guard let statusCode else { return false }
        return (200..<300).contains(statusCode) && errorDescription == nil
    }

    var summary: String {
        if let errorDescription { return errorDescription }
        if let statusCode { return "HTTP \(statusCode)" }
        return "Pending"
    }
}

@Observable
final class DebugLogStore: @unchecked Sendable {
    static let shared = DebugLogStore()

    private let enabledKey = "podimo_debug_enabled"
    private let maxEntries = 100

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }

    private(set) var entries: [DebugLogEntry] = []

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    }

    func record(_ entry: DebugLogEntry) {
        guard isEnabled else { return }
        NSLog("[PodimoAPI] %@ -> %@ (%@)", entry.operationName, entry.summary, entry.requestURL)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }
}