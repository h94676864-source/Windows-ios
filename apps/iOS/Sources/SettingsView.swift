import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Backend", value: "Not configured")
                    LabeledContent("Transport", value: "Planned: WebRTC")
                }
                Section("Compatibility") {
                    LabeledContent("Minimum iOS", value: "17.0")
                    LabeledContent("Execution", value: "Cloud workstation")
                }
                Section("About") {
                    LabeledContent("Version", value: "0.1.0-dev")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
