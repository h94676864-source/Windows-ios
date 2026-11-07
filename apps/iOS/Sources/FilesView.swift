import SwiftUI
import UniformTypeIdentifiers

private struct FilesContainer: Codable, Identifiable {
    var id: UUID
    var name: String
}

private struct DriveMap: Codable, Identifiable {
    var id: String { letter }
    var letter: String
    var relativePath: String
}

struct FilesView: View {
    @State private var containers = Self.loadContainers()
    @State private var selectedContainerID: UUID?
    @State private var selectedDrive = "C:"
    @State private var currentRelativePath = ""
    @State private var entries: [URL] = []
    @State private var showingNewFolder = false
    @State private var folderName = ""
    @State private var errorMessage: String?
    @State private var driveMaps: [DriveMap] = []

    private let fileManager = FileManager.default
    private let drives = ["C:", "D:"]

    var body: some View {
        NavigationStack {
            Group {
                if containers.isEmpty {
                    ContentUnavailableView("No containers", systemImage: "shippingbox",
                        description: Text("Create a container in the Winlator tab first."))
                } else {
                    VStack(spacing: 0) {
                        Picker("Container", selection: $selectedContainerID) {
                            ForEach(containers) { container in
                                Text(container.name).tag(Optional(container.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal)
                        Picker("Drive", selection: $selectedDrive) {
                            ForEach(drives, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        HStack {
                            Text(drivePathLabel).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button("Up", systemImage: "arrow.up") { goUp() }
                                .disabled(currentRelativePath.isEmpty)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        Divider()
                        if entries.isEmpty {
                            ContentUnavailableView("Folder is empty", systemImage: "folder",
                                description: Text("Use + to create a folder or import files into this container."))
                        } else {
                            List {
                                ForEach(entries, id: \.path) { url in
                                    Button { open(url) } label: {
                                        Label(url.lastPathComponent,
                                            systemImage: isDirectory(url) ? "folder.fill" : fileIcon(url))
                                            .foregroundStyle(.primary)
                                    }
                                    .contextMenu {
                                        Button("Rename", systemImage: "pencil") { rename(url) }
                                        Button("Delete", systemImage: "trash", role: .destructive) { delete(url) }
                                    }
                                }
                            }
                            .listStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Files")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New folder", systemImage: "folder.badge.plus") { showingNewFolder = true }
                        Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
                    } label: { Image(systemName: "plus.circle.fill") }
                }
            }
            .onAppear { refresh() }
            .onChange(of: selectedContainerID) { _, _ in currentRelativePath = ""; refresh() }
            .onChange(of: selectedDrive) { _, _ in currentRelativePath = ""; refresh() }
            .onChange(of: containers.count) { _, _ in refresh() }
            .alert("New folder", isPresented: $showingNewFolder) {
                TextField("Folder name", text: $folderName)
                Button("Cancel", role: .cancel) { folderName = "" }
                Button("Create") { createFolder() }
            }
            .alert("File operation", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var drivePathLabel: String { selectedDrive + "\\" + currentRelativePath.replacingOccurrences(of: "/", with: "\\") }

    private func containerRoot() -> URL? {
        guard let id = selectedContainerID else { return nil }
        do {
            let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return base.appendingPathComponent("Winlator/Containers/\(id.uuidString)", isDirectory: true)
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    private func driveRoot() -> URL? {
        guard let root = containerRoot() else { return nil }
        let relative = selectedDrive == "C:" ? "prefix/drive_c" : "downloads"
        return root.appendingPathComponent(relative, isDirectory: true)
    }

    private func currentFolder() -> URL? {
        guard let base = driveRoot() else { return nil }
        let components = currentRelativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") }) else {
            return nil
        }
        var candidate = base
        for component in components { candidate.appendPathComponent(String(component), isDirectory: true) }
        let rootPath = base.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/"),
              candidate.resolvingSymlinksInPath().path == rootPath ||
              candidate.resolvingSymlinksInPath().path.hasPrefix(rootPath + "/") else { return nil }
        return candidate
    }

    private func refresh() {
        guard let root = containerRoot() else { entries = []; return }
        do {
            let config = root.appendingPathComponent("config/drives.json")
            if let data = try? Data(contentsOf: config) {
                driveMaps = (try? JSONDecoder().decode([DriveMap].self, from: data)) ?? []
            } else {
                driveMaps = [DriveMap(letter: "C:", relativePath: "prefix/drive_c"),
                             DriveMap(letter: "D:", relativePath: "downloads")]
                try saveDriveMaps(root: root)
            }
            guard let folder = currentFolder() else { entries = []; return }
            guard let drive = driveRoot(),
                  folder.standardizedFileURL.path == drive.standardizedFileURL.path ||
                  folder.standardizedFileURL.path.hasPrefix(drive.standardizedFileURL.path + "/") else {
                throw FileManagerViewError.invalidPath
            }
            let resolvedFolder = folder.resolvingSymlinksInPath()
            guard resolvedFolder.path == drive.resolvingSymlinksInPath().path ||
                  resolvedFolder.path.hasPrefix(drive.resolvingSymlinksInPath().path + "/") else {
                throw FileManagerViewError.invalidPath
            }
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            entries = try fileManager.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]).sorted {
                    let lhs = isDirectory($0), rhs = isDirectory($1)
                    return lhs == rhs ? $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending : lhs
                }
        } catch { errorMessage = error.localizedDescription; entries = [] }
    }

    private func saveDriveMaps(root: URL) throws {
        let config = root.appendingPathComponent("config", isDirectory: true)
        try fileManager.createDirectory(at: config, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(driveMaps)
        try data.write(to: config.appendingPathComponent("drives.json"), options: .atomic)
    }

    private func open(_ url: URL) {
        guard isDirectory(url) else {
            errorMessage = "File selected: \(url.lastPathComponent). Windows execution is not connected yet."
            return
        }
        guard let base = driveRoot(), isSafeDirectChild(url, of: currentFolder() ?? base) else {
            errorMessage = "This item is outside the current container folder."
            return
        }
        let resolved = url.resolvingSymlinksInPath()
        let root = base.resolvingSymlinksInPath().path
        guard resolved.path.hasPrefix(root + "/") else {
            errorMessage = "Opening a linked folder outside this drive is blocked."
            return
        }
        let relative = url.standardizedFileURL.path.replacingOccurrences(of: base.standardizedFileURL.path + "/", with: "")
        currentRelativePath = relative
        refresh()
    }

    private func goUp() {
        let parts = currentRelativePath.split(separator: "/")
        currentRelativePath = parts.dropLast().joined(separator: "/")
        refresh()
    }

    private func createFolder() {
        defer { folderName = "" }
        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":"),
              let folder = currentFolder() else { return }
        do {
            let destination = folder.appendingPathComponent(name, isDirectory: true).standardizedFileURL
            guard isContained(destination, in: driveRoot() ?? folder) else {
                throw FileManagerViewError.invalidPath
            }
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    private func rename(_ url: URL) {
        let alert = UIAlertController(title: "Rename", message: url.lastPathComponent, preferredStyle: .alert)
        alert.addTextField { $0.text = url.lastPathComponent }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            guard let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, !name.contains("/"), !name.contains("\\"), !name.contains(":"),
                  !name.contains("\0"), isSafeDirectChild(url, of: currentFolder() ?? url.deletingLastPathComponent()) else { return }
            do {
                let destination = url.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
                guard isContained(destination, in: driveRoot() ?? url.deletingLastPathComponent()),
                      !fileManager.fileExists(atPath: destination.path) else {
                    throw FileManagerViewError.invalidPath
                }
                try fileManager.moveItem(at: url, to: destination)
                refresh()
            } catch { errorMessage = error.localizedDescription }
        })
        UIApplication.shared.topMostViewController?.present(alert, animated: true)
    }

    private func delete(_ url: URL) {
        guard isSafeDirectChild(url, of: currentFolder() ?? url.deletingLastPathComponent()) else {
            errorMessage = "This item is outside the current container folder."
            return
        }
        do { try fileManager.removeItem(at: url); refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    private func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath.hasPrefix(rootPath + "/")
    }

    private func isSafeDirectChild(_ item: URL, of folder: URL) -> Bool {
        item.standardizedFileURL.deletingLastPathComponent() == folder.standardizedFileURL &&
        item.standardizedFileURL.lastPathComponent != "." &&
        item.standardizedFileURL.lastPathComponent != ".."
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func fileIcon(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "exe", "msi": return "app"
        case "txt", "log", "md": return "doc.text"
        case "zip", "7z", "rar": return "archivebox"
        default: return "doc"
        }
    }

    private static func loadContainers() -> [FilesContainer] {
        guard let data = UserDefaults.standard.data(forKey: "winlator.containers") else { return [] }
        return (try? JSONDecoder().decode([FilesContainer].self, from: data)) ?? []
    }
}

private extension UIApplication {
    var topMostViewController: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let root = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}


private enum FileManagerViewError: LocalizedError {
    case invalidPath

    var errorDescription: String? {
        "The requested file operation is outside the selected drive or would overwrite an existing item."
    }
}
