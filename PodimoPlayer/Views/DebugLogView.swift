import SwiftUI

struct DebugLogView: View {
    @State private var store = DebugLogStore.shared

    var body: some View {
        List {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No requests yet",
                    systemImage: "ladybug",
                    description: Text("Requests will appear here once debug logging is on and you use the app.")
                )
            } else {
                ForEach(store.entries) { entry in
                    NavigationLink(value: entry) {
                        DebugLogRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle("Request Log")
        .navigationDestination(for: DebugLogEntry.self) { entry in
            DebugLogDetailView(entry: entry)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) { store.clear() }
                    .disabled(store.entries.isEmpty)
            }
        }
    }
}

private struct DebugLogRow: View {
    let entry: DebugLogEntry

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(entry.isSuccess ? Color.podimoMint : Color.podimoCoral)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.operationName).font(.subheadline.weight(.semibold))
                Text(entry.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.date.formatted(date: .omitted, time: .standard))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DebugLogDetailView: View {
    let entry: DebugLogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Status", entry.summary)
                section("URL", entry.requestURL)
                section("Headers", entry.requestHeaders.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n"))
                section("Request Body", entry.requestBody)
                section("Response Body", entry.responseBody ?? "—")
            }
            .padding()
        }
        .navigationTitle(entry.operationName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText)
            }
        }
    }

    private var shareText: String {
        "\(entry.operationName)\n\(entry.summary)\n\nRequest:\n\(entry.requestBody)\n\nResponse:\n\(entry.responseBody ?? "—")"
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(body)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

extension DebugLogEntry: Hashable {
    static func == (lhs: DebugLogEntry, rhs: DebugLogEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
