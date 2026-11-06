import SwiftUI

struct WorkspacesView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No workspaces yet",
                systemImage: "desktopcomputer",
                description: Text("Windows and Linux cloud workspaces will appear here after the session service is connected.")
            )
            .navigationTitle("Workspaces")
        }
    }
}
