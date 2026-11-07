import SwiftUI
import UniformTypeIdentifiers

struct WinlatorContainer: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var windowsVersion: String = "Windows 10"
    var architecture: String = "WoW64"
    var graphicsDriver: String = "SwiftShader (compatibility)"
    var box64Preset: String = "Compatibility"
}

private struct WinlatorShortcut: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var filename: String
    var localPath: String
    var containerID: UUID?
}

struct WinlatorManagerView: View {
    @State private var containers = Self.load([WinlatorContainer].self, key: "winlator.containers")
    @State private var shortcuts = Self.load([WinlatorShortcut].self, key: "winlator.shortcuts")
    @State private var showingNewContainer = false
    @State private var showingImporter = false
    @State private var showingRuntimeInfo = false
    @State private var selectedContainer: WinlatorContainer?
    @State private var selectedShortcut: WinlatorShortcut?
    @State private var launchMessage: String?
    @State private var newContainerName = "My Windows Container"
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            ScrollView { pageContent }
            .navigationTitle("Winlator")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Create container", systemImage: "plus") { showingNewContainer = true }
                        Button("Import Windows EXE", systemImage: "square.and.arrow.down") { showingImporter = true }
                    } label: { Image(systemName: "plus.circle.fill") }
                }
            }
            .sheet(item: $selectedShortcut) { shortcut in
                WindowsAppLauncherSheet(shortcut: shortcut, containers: containers,
                    onAssign: { updated, containerID in
                        if let index = shortcuts.firstIndex(where: { $0.id == updated.id }) {
                            shortcuts[index].containerID = containerID
                            Self.save(shortcuts, key: "winlator.shortcuts")
                        }
                    },
                    onLaunch: { app, container in
                        launchMessage = WinlatorWineExecutionBridge.preflight(
                            executableURL: URL(fileURLWithPath: app.localPath), container: container
                        )
                    })
            }
            .sheet(item: $selectedContainer) { container in
                ContainerSettingsView(container: container) { updated in
                    if let index = containers.firstIndex(where: { $0.id == updated.id }) {
                        containers[index] = updated
                        Self.save(containers, key: "winlator.containers")
                    }
                }
            }
            .alert("Create container", isPresented: $showingNewContainer) {
                TextField("Container name", text: $newContainerName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    let name = newContainerName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        let container = WinlatorContainer(name: name)
                        do {
                            try WinlatorContainerStorage.createLayout(for: container)
                            containers.append(container)
                            Self.save(containers, key: "winlator.containers")
                        } catch {
                            importError = error.localizedDescription
                        }
                    }
                    newContainerName = "My Windows Container"
                }
            } message: {
                Text("Create a Windows environment profile.")
            }
            .fileImporter(isPresented: $showingImporter,
                allowedContentTypes: [UTType(filenameExtension: "exe") ?? .data, UTType(filenameExtension: "msi") ?? .data],
                allowsMultipleSelection: true, onCompletion: importExecutables)
            .alert("Windows app launch", isPresented: Binding(
                get: { launchMessage != nil },
                set: { if !$0 { launchMessage = nil } }
            )) {
                Button("OK", role: .cancel) { launchMessage = nil }
            } message: {
                Text(launchMessage ?? "")
            }
            .alert("Runtime information", isPresented: $showingRuntimeInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The installer is imported and listed, but launching Windows binaries requires a compatible Wine and CPU translation runtime. That execution engine is not available in this iOS build.")
            }
            .alert("Import / RootFS status", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: { Text(importError ?? "Unknown import error.") }
        }
    }

    private var pageContent: some View {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("WINLATOR").font(.caption.weight(.bold)).tracking(2.5).foregroundStyle(.cyan)
                        Text("Windows apps on iPhone").font(.largeTitle.bold())
                        Text("Manage containers, import installers and configure compatibility profiles.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "cpu").font(.title2).foregroundStyle(.orange)
                            .frame(width: 44, height: 44)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Execution engine").font(.headline)
                            Text("iOS runtime port in progress").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle().fill(.orange).frame(width: 8, height: 8)
                    }
                    .padding(14)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                    HStack {
                        Text("Containers").font(.title2.bold())
                        Spacer()
                        Button("New", systemImage: "plus") { showingNewContainer = true }
                    }
                    if containers.isEmpty {
                        ContentUnavailableView("No containers yet", systemImage: "shippingbox",
                            description: Text("Create a Windows environment profile to organize applications and settings."))
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(containers) { container in
                            Button { selectedContainer = container } label: {
                                VStack(alignment: .leading, spacing: 11) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "pc").font(.title2).foregroundStyle(.cyan)
                                            .frame(width: 44, height: 44)
                                            .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(container.name).font(.headline).foregroundStyle(.primary)
                                            Text(container.windowsVersion + " • " + container.architecture)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        Text(container.box64Preset).font(.caption2)
                                        Text("•")
                                        Text(container.graphicsDriver).font(.caption2).lineLimit(1)
                                        Spacer()
                                        Text("PROFILE").font(.system(size: 9, weight: .bold)).tracking(0.8)
                                    }.foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Text("Windows applications").font(.title2.bold())
                        Spacer()
                        Button("Import EXE", systemImage: "square.and.arrow.down") { showingImporter = true }
                    }
                    if shortcuts.isEmpty {
                        VStack(spacing: 9) {
                            Image(systemName: "shippingbox").font(.system(size: 30)).foregroundStyle(.secondary)
                            Text("No installers imported").font(.headline)
                            Text("Add an .EXE or .MSI file from the Files app.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Import installer", systemImage: "plus") { showingImporter = true }
                                .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        ForEach(shortcuts) { shortcut in
                            HStack(spacing: 12) {
                                Image(systemName: "app").font(.title3).foregroundStyle(.indigo)
                                    .frame(width: 42, height: 42)
                                    .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(shortcut.name).font(.subheadline.weight(.semibold))
                                    Text(shortcut.filename).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Text("Container: " + (containers.first(where: { $0.id == shortcut.containerID })?.name ?? "Unassigned"))
                                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                }
                                Spacer()
                                Button { selectedShortcut = shortcut } label: {
                                    Image(systemName: "play.fill").font(.caption.weight(.bold))
                                        .foregroundStyle(.white).frame(width: 34, height: 34)
                                        .background(.cyan, in: Circle())
                                }
                                .accessibilityLabel("Open app launcher")
                            }
                            .padding(11)
                            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                            .contextMenu {
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    removeShortcut(shortcut)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Runtime port status", systemImage: "info.circle").font(.subheadline.weight(.semibold))
                        Text("This build provides container profiles and local installer import. The Android Winlator engine (Wine, Box86/Box64, Linux root filesystem and graphics drivers) has not been ported to iOS. Imported EXE files are stored locally and cannot execute in this build.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding()
    }

    private func importExecutables(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            let manager = FileManager.default
            let folder = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ImportedWindowsApps", isDirectory: true)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for source in urls {
                let hasAccess = source.startAccessingSecurityScopedResource()
                defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
                let destination = folder.appendingPathComponent(source.lastPathComponent)
                if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
                try manager.copyItem(at: source, to: destination)
                shortcuts.append(WinlatorShortcut(
                    name: source.deletingPathExtension().lastPathComponent,
                    filename: source.lastPathComponent,
                    localPath: destination.path,
                    containerID: containers.first?.id
                ))
            }
            Self.save(shortcuts, key: "winlator.shortcuts")
        } catch {
            importError = error.localizedDescription
        }
    }

    private func removeShortcut(_ shortcut: WinlatorShortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
        try? FileManager.default.removeItem(atPath: shortcut.localPath)
        Self.save(shortcuts, key: "winlator.shortcuts")
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(type, from: data) else { return [] as! T }
        return value
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}


private struct WindowsAppLauncherSheet: View {
    @Environment(\.dismiss) private var dismiss
    let shortcut: WinlatorShortcut
    let containers: [WinlatorContainer]
    let onAssign: (WinlatorShortcut, UUID?) -> Void
    let onLaunch: (WinlatorShortcut, WinlatorContainer?) -> Void
    @State private var selectedContainerID: UUID?

    init(shortcut: WinlatorShortcut, containers: [WinlatorContainer],
         onAssign: @escaping (WinlatorShortcut, UUID?) -> Void,
         onLaunch: @escaping (WinlatorShortcut, WinlatorContainer?) -> Void) {
        self.shortcut = shortcut
        self.containers = containers
        self.onAssign = onAssign
        self.onLaunch = onLaunch
        _selectedContainerID = State(initialValue: shortcut.containerID ?? containers.first?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Windows application") {
                    LabeledContent("Name", value: shortcut.name)
                    LabeledContent("Installer", value: shortcut.filename)
                    LabeledContent("File", value: URL(fileURLWithPath: shortcut.localPath).lastPathComponent)
                }
                Section("Container") {
                    if containers.isEmpty {
                        Text("Create a container before launching an app.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Picker("Run in", selection: $selectedContainerID) {
                            ForEach(containers) { container in
                                Text(container.name).tag(Optional(container.id))
                            }
                        }
                        Button("Save container assignment") {
                            onAssign(shortcut, selectedContainerID)
                        }
                        .disabled(selectedContainerID == shortcut.containerID)
                    }
                }
                Section("Execution") {
                    let runtime = WinlatorWineRuntimeStorage.status()
                    LabeledContent("Wine runtime", value: runtime.title)
                    Text(runtime.detail).font(.footnote).foregroundStyle(.secondary)
                    Button {
                        let container = containers.first(where: { $0.id == selectedContainerID })
                        onLaunch(shortcut, container)
                        dismiss()
                    } label: {
                        Label("Check and launch", systemImage: "play.fill")
                    }
                    .disabled(containers.isEmpty || selectedContainerID == nil)
                }
            }
            .navigationTitle("App launcher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ContainerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var container: WinlatorContainer
    @State private var prefixMessage: String?
    let onSave: (WinlatorContainer) -> Void
    private let versions = ["Windows 11", "Windows 10", "Windows 8.1", "Windows 7", "Windows XP"]
    private let presets = ["Compatibility", "Performance", "Stability", "Aggressive"]
    private let drivers = ["SwiftShader (compatibility)", "OpenGL ES (future)", "Vulkan (future)"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Container") {
                    TextField("Name", text: $container.name)
                    Picker("Windows version", selection: $container.windowsVersion) {
                        ForEach(versions, id: \.self) { Text($0) }
                    }
                    Picker("Architecture", selection: $container.architecture) {
                        Text("WoW64").tag("WoW64")
                        Text("x86").tag("x86")
                        Text("x64").tag("x64")
                    }
                }
                Section("Wine prefix") {
                    LabeledContent("Prefix state", value: WinlatorWinePrefixStorage.status(for: container))
                    Button("Prepare Wine prefix", systemImage: "folder.badge.gearshape") {
                        do {
                            prefixMessage = try WinlatorWinePrefixStorage.prepare(for: container)
                        } catch {
                            prefixMessage = error.localizedDescription
                        }
                    }
                    Text("Creates the Windows C: directory layout and prefix metadata. Wine must run wineboot before this becomes a usable Windows prefix.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Wine runtime") {
                    LabeledContent("Runtime", value: WinlatorWineRuntimeStorage.status().title)
                    Text(WinlatorWineRuntimeStorage.status().detail)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("CPU translation runtimes") {
                    let translation = WinlatorCPUTranslationRuntimeStorage.status()
                    LabeledContent("Box64", value: translation.box64.title)
                    Text(translation.box64.detail)
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Box86", value: translation.box86.title)
                    Text(translation.box86.detail)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Graphics runtime") {
                    let graphics = WinlatorGraphicsRuntimeStorage.status()
                    LabeledContent("Metal GPU", value: graphics.metal.title)
                    Text(graphics.metal.detail)
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Vulkan / MoltenVK", value: graphics.vulkan.title)
                    Text(graphics.vulkan.detail)
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("DirectX translation bridge", value: graphics.bridge.title)
                    Text(graphics.bridge.detail)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Compatibility") {
                    Picker("CPU preset", selection: $container.box64Preset) {
                        ForEach(presets, id: \.self) { Text($0) }
                    }
                    Picker("Graphics driver", selection: $container.graphicsDriver) {
                        ForEach(drivers, id: \.self) { Text($0) }
                    }
                }
                Section {
                    Label("These are saved profiles. They take effect only when an iOS-compatible execution engine is available.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Container settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Wine prefix", isPresented: Binding(
                get: { prefixMessage != nil },
                set: { if !$0 { prefixMessage = nil } }
            )) {
                Button("OK", role: .cancel) { prefixMessage = nil }
            } message: {
                Text(prefixMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(container); dismiss() }
                }
            }
        }
    }
}
