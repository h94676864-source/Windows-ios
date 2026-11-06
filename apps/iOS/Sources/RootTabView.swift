import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "desktopcomputer") }

            WorkspacesView()
                .tabItem { Label("Workspaces", systemImage: "pc") }

            FilesView()
                .tabItem { Label("Files", systemImage: "folder") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.cyan)
    }
}
