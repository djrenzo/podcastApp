import SwiftUI

struct SettingsView: View {
    @State private var credentials = CredentialsStore.shared
    @State private var debugLog = DebugLogStore.shared
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSucceeded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Podimo credentials") {
                    TextField("Cookie", text: $credentials.cookie, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Authorization token", text: $credentials.authToken, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            if isTesting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isTesting || !credentials.hasCredentials)

                    if let testResult {
                        Label(testResult, systemImage: testSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(testSucceeded ? Color.podimoMint : Color.podimoCoral)
                            .font(.footnote)
                    }
                }

                Section {
                    Button("Clear credentials", role: .destructive) {
                        credentials.clear()
                        testResult = nil
                    }
                }

                Section("Debugging") {
                    Toggle("Enable request logging", isOn: $debugLog.isEnabled)
                    NavigationLink("View Request Log") {
                        DebugLogView()
                    }
                    Text("Logs every GraphQL request and response, including headers and bodies, to help diagnose errors like a 404.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    Text("Paste the Cookie header and Authorization bearer token from an active open.podimo.com session. These are stored locally on this device and sent with every request.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func testConnection() async {
        isTesting = true
        do {
            _ = try await PodimoAPI.shared.getLibrary()
            testSucceeded = true
            testResult = "Connected successfully."
        } catch {
            testSucceeded = false
            testResult = error.localizedDescription
        }
        isTesting = false
    }
}
