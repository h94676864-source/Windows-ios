import SwiftUI

struct WorkspacesView: View {
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @State private var workspaces: [RemoteWorkspace] = []
    @State private var workspaceName = "My Windows PC"
    @State private var selectedOS: WorkspaceOperatingSystem = .windows
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var message: String?
    @State private var showingCreate = false

    var body: some View {
        NavigationStack {
            Group {
                if backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Backend not configured",
                        systemImage: "network",
                        description: Text("Add your cloud control-plane URL in Settings before creating a remote PC.")
                    )
                } else if isLoading && workspaces.isEmpty {
                    ProgressView("Loading workspaces…")
                } else if workspaces.isEmpty {
                    ContentUnavailableView {
                        Label("No workspaces yet", systemImage: "desktopcomputer")
                    } description: {
                        Text("Create a Windows or Linux cloud workstation. The backend provisions the machine and returns its session status.")
                    } actions: {
                        Button("Create workspace") { showingCreate = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                    }
                } else {
                    List {
                        ForEach(workspaces) { workspace in
                            WorkspaceRow(workspace: workspace) {
                                Task { await stop(workspace) }
                            }
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Workspaces")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(backendBaseURL.isEmpty)
                    .accessibilityLabel("Create workspace")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
            }
            .sheet(isPresented: $showingCreate) {
                createSheet
                    .presentationDetents([.medium])
            }
            .task {
                if !backendBaseURL.isEmpty { await load() }
            }
        }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section("New cloud workstation") {
                    TextField("Workspace name", text: $workspaceName)
                    Picker("Operating system", selection: $selectedOS) {
                        ForEach(WorkspaceOperatingSystem.allCases) { os in
                            Label(os.title, systemImage: os.symbol).tag(os)
                        }
                    }
                }
                Section {
                    Text("The cloud service must be deployed and configured in Settings. Machine usage may incur provider charges.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create workspace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCreate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Creating…" : "Create") {
                        Task { await create() }
                    }
                    .disabled(isCreating || workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @MainActor
    private func load() async {
        guard let url = URL(string: backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            message = "Set a valid backend URL in Settings."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            workspaces = try await BackendClient(baseURL: url).listWorkspaces()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func create() async {
        guard let url = URL(string: backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let created = try await BackendClient(baseURL: url).createWorkspace(
                name: workspaceName.trimmingCharacters(in: .whitespacesAndNewlines),
                operatingSystem: selectedOS
            )
            workspaces.insert(created, at: 0)
            showingCreate = false
            message = "\(created.name) created — status: \(created.status)"
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func stop(_ workspace: RemoteWorkspace) async {
        guard let url = URL(string: backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        do {
            try await BackendClient(baseURL: url).stopWorkspace(id: workspace.id)
            workspaces.removeAll { $0.id == workspace.id }
            message = "\(workspace.name) stop requested."
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct WorkspaceRow: View {
    let workspace: RemoteWorkspace
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: workspace.operatingSystem.symbol)
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(width: 44, height: 44)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(workspace.name).font(.headline)
                Text("\(workspace.operatingSystem.title) · \(workspace.status.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Stop workspace", role: .destructive, action: onStop)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .padding(.vertical, 5)
    }
}
