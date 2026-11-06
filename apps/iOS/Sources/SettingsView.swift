import SwiftUI

struct SettingsView: View {
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @State private var healthMessage = "Not tested"
    @State private var isChecking = false
    @State private var isHealthy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("https://your-backend.example", text: $backendBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Backend URL")

                    Button {
                        Task { await checkBackend() }
                    } label: {
                        HStack {
                            Text("Test connection")
                            Spacer()
                            if isChecking {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isChecking || backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Label(healthMessage, systemImage: isHealthy ? "checkmark.circle.fill" : "info.circle")
                        .font(.footnote)
                        .foregroundStyle(isHealthy ? .green : .secondary)
                        .textSelection(.enabled)
                }

                Section("Compatibility") {
                    LabeledContent("Minimum iOS", value: "17.0")
                    LabeledContent("Execution", value: "Cloud workstation")
                    LabeledContent("Remote transport", value: "Not connected")
                }

                Section("About") {
                    LabeledContent("Version", value: "0.2.0-dev")
                }
            }
            .navigationTitle("Settings")
        }
    }

    @MainActor
    private func checkBackend() async {
        isChecking = true
        isHealthy = false
        defer { isChecking = false }

        let rawURL = backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host != nil else {
            healthMessage = "Enter a valid backend URL beginning with https://."
            return
        }

        do {
            let result = try await BackendClient(baseURL: url).checkHealth()
            healthMessage = result
            isHealthy = true
        } catch {
            healthMessage = error.localizedDescription
        }
    }
}
