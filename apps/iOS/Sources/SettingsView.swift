import SwiftUI

struct SettingsView: View {
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @State private var tokenDraft = ""
    @State private var tokenMessage = "No token saved"
    @State private var healthMessage = "Not tested"
    @State private var isChecking = false
    @State private var isHealthy = false
    @StateObject private var deviceServices = WinlatorDeviceServices()

    var body: some View {
        NavigationStack {
            Form {
                Section("Device audio") {
                    LabeledContent("Audio session", value: deviceServices.audioSessionStatus)
                    LabeledContent("Output", value: deviceServices.audioOutput)
                    LabeledContent("Input", value: deviceServices.audioInput)
                    Button("Refresh audio status") { deviceServices.refreshAudioStatus() }
                }

                Section("Network") {
                    Label(deviceServices.networkStatus, systemImage: deviceServices.networkAvailable ? "wifi" : "wifi.slash")
                        .foregroundStyle(deviceServices.networkAvailable ? .green : .secondary)
                    LabeledContent("Connection type", value: deviceServices.networkType)
                    LabeledContent("Expensive network", value: deviceServices.isExpensiveNetwork ? "Yes" : "No")
                    LabeledContent("Constrained network", value: deviceServices.isConstrainedNetwork ? "Yes" : "No")
                }

                Section("Connection") {
                    TextField("https://your-backend.example", text: $backendBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Backend URL")
                    SecureField("Backend access token", text: $tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Backend bearer token")
                    HStack {
                        Button("Save token") { saveToken() }
                            .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                        Button("Remove", role: .destructive) { removeToken() }
                    }
                    Text(tokenMessage).font(.footnote).foregroundStyle(.secondary)
                    Button {
                        Task { await checkBackend() }
                    } label: {
                        HStack {
                            Text("Test connection")
                            Spacer()
                            if isChecking { ProgressView() }
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
                    LabeledContent("Version", value: "0.3.0-dev")
                }
            }
            .navigationTitle("Settings")
            .task { loadTokenStatus() }
        }
    }

    private func loadTokenStatus() {
        do {
            tokenMessage = try SecureTokenStore.read() == nil ? "No token saved" : "Access token stored securely in iOS Keychain"
        } catch { tokenMessage = error.localizedDescription }
    }

    private func saveToken() {
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        do {
            try SecureTokenStore.save(token)
            tokenDraft = ""
            tokenMessage = "Access token stored securely in iOS Keychain"
        } catch { tokenMessage = error.localizedDescription }
    }

    private func removeToken() {
        do {
            try SecureTokenStore.delete()
            tokenDraft = ""
            tokenMessage = "No token saved"
        } catch { tokenMessage = error.localizedDescription }
    }

    @MainActor
    private func checkBackend() async {
        isChecking = true
        isHealthy = false
        defer { isChecking = false }
        let rawURL = backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else {
            healthMessage = "Enter a valid backend URL beginning with https://."
            return
        }
        do {
            let result = try await BackendClient(baseURL: url).checkHealth()
            healthMessage = result
            isHealthy = true
        } catch { healthMessage = error.localizedDescription }
    }
}
