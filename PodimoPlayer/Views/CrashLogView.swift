import SwiftUI

struct CrashLogView: View {
    @State private var store = CrashLogStore.shared

    var body: some View {
        List {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No crashes logged",
                    systemImage: "checkmark.seal",
                    description: Text("If the app crashes, details will show up here the next time you open it.")
                )
            } else {
                ForEach(store.entries) { entry in
                    NavigationLink {
                        CrashLogDetailView(entry: entry)
                    } label: {
                        CrashLogRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle("Crash Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) { store.clear() }
                    .disabled(store.entries.isEmpty)
            }
        }
    }
}

private struct CrashLogRow: View {
    let entry: CrashLogEntry

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.podimoCoral)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.subheadline.weight(.semibold))
                Text(entry.date.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CrashLogDetailView: View {
    let entry: CrashLogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.date.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.detail)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: entry.detail)
            }
        }
    }
}
