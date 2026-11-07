import SwiftUI
import UniformTypeIdentifiers

struct WinlatorInstallerManagerView: View {
    let container: WinlatorContainer
    @State private var installers: [WinlatorInstallerRecord] = []
    @State private var showingImporter = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if installers.isEmpty {
                ContentUnavailableView("No installers", systemImage: "shippingbox",
                    description: Text("Import EXE/MSI files into this container's C: drive."))
            } else {
                ForEach(installers) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.headline)
                        Text(item.fileURL.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contextMenu {
                        Button("Remove installer", systemImage: "trash", role: .destructive) {
                            remove(item)
                        }
                    }
                }
                .onDelete(perform: deleteOffsets)
            }
        }
        .navigationTitle("Container installers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import", systemImage: "plus") { showingImporter = true }
            }
        }
        .fileImporter(isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "exe") ?? .data,
                                  UTType(filenameExtension: "msi") ?? .data],
            allowsMultipleSelection: true, onCompletion: importFiles)
        .alert("Installer manager", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onAppear(perform: reload)
    }

    private func reload() {
        do { installers = try WinlatorInstallerStorage.list(for: container) }
        catch { errorMessage = error.localizedDescription }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            for url in try result.get() {
                _ = try WinlatorInstallerStorage.importInstaller(from: url, for: container)
            }
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    private func remove(_ item: WinlatorInstallerRecord) {
        do { try WinlatorInstallerStorage.remove(item, for: container); reload() }
        catch { errorMessage = error.localizedDescription }
    }

    private func deleteOffsets(_ offsets: IndexSet) {
        for index in offsets { remove(installers[index]) }
    }
}
