import SwiftUI

struct FilesView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Cloud storage not connected",
                systemImage: "folder",
                description: Text("A secure file browser and transfer flow will be added with the backend.")
            )
            .navigationTitle("Files")
        }
    }
}
