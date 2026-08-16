import Foundation
import Observation

struct CrashLogEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let title: String
    let detail: String

    init(title: String, detail: String) {
        self.id = UUID()
        self.date = Date()
        self.title = title
        self.detail = detail
    }
}

@Observable
final class CrashLogStore: @unchecked Sendable {
    static let shared = CrashLogStore()

    private let enabledKey = "podimo_crashlog_enabled"
    private let entriesKey = "podimo_crashlog_entries"
    private let maxEntries = 20

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }

    private(set) var entries: [CrashLogEntry] = []

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        load()
    }

    func record(title: String, detail: String) {
        guard isEnabled else { return }
        entries.insert(CrashLogEntry(title: title, detail: detail), at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: entriesKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: entriesKey),
           let decoded = try? JSONDecoder().decode([CrashLogEntry].self, from: data) {
            entries = decoded
        }
    }
}
