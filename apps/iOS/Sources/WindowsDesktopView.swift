import SwiftUI

private enum DesktopApp: String, CaseIterable, Identifiable {
    case thisPC = "This PC"
    case browser = "Edge"
    case vscode = "Visual Studio Code"
    case ida = "IDA Pro"
    case terminal = "Terminal"
    case recycle = "Recycle Bin"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .thisPC: return "desktopcomputer"
        case .browser: return "globe"
        case .vscode: return "chevron.left.forwardslash.chevron.right"
        case .ida: return "magnifyingglass"
        case .terminal: return "terminal"
        case .recycle: return "trash"
        }
    }

    var tint: Color {
        switch self {
        case .thisPC: return .cyan
        case .browser: return .blue
        case .vscode: return .indigo
        case .ida: return .orange
        case .terminal: return .green
        case .recycle: return .gray
        }
    }

    var detail: String {
        switch self {
        case .thisPC: return "Drives and folders will appear here when a remote Windows session is connected."
        case .browser: return "Microsoft Edge shortcut preview. A remote session launches the browser on the Windows host."
        case .vscode: return "Visual Studio Code workspace shortcut. Connect a provisioned workstation to open your projects."
        case .ida: return "IDA Pro workstation shortcut. Install your licensed copy on the remote Windows or Linux machine."
        case .terminal: return "Windows Terminal shortcut. Commands execute on the remote machine after session connection."
        case .recycle: return "The recycle bin on your remote Windows desktop will be shown here."
        }
    }
}

struct WindowsDesktopView: View {
    @State private var showingStart = false
    @State private var selectedApp: DesktopApp?
    @State private var showingConnectInfo = false
    @State private var showingTouchControls = false
    @State private var showingKeyboard = false
    @State private var lastTouchAction = ""
    @State private var showingMousePad = false
    @State private var showingGamepadStatus = false
    @StateObject private var gameControllerMonitor = WinlatorGameControllerMonitor()

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.02, green: 0.20, blue: 0.37), Color(red: 0.02, green: 0.09, blue: 0.20), Color(red: 0.01, green: 0.04, blue: 0.11)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.cyan.opacity(0.14))
                    .frame(width: proxy.size.width * 0.95)
                    .blur(radius: 36)
                    .offset(x: proxy.size.width * 0.42, y: -proxy.size.height * 0.22)

                VStack(spacing: 0) {
                    HStack {
                        Label("WINLATOR OS", systemImage: "windows")
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                        Spacer()
                        HStack(spacing: 5) {
                            Circle().fill(.orange).frame(width: 7, height: 7)
                            Text("PREVIEW MODE").font(.system(size: 9, weight: .bold)).tracking(0.8)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.black.opacity(0.25), in: Capsule())
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(DesktopApp.allCases) { app in
                            Button {
                                selectedApp = app
                            } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: app.symbol)
                                        .font(.system(size: 27, weight: .medium))
                                        .foregroundStyle(app.tint)
                                        .frame(width: 54, height: 48)
                                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12), lineWidth: 1))
                                    Text(app.rawValue)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 30)

                    Spacer()

                    if showingStart {
                        startMenu
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }

                    taskbar
                }
            }
            .clipShape(Rectangle())
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showingStart)
            .sheet(item: $selectedApp) { app in
                appWindow(app)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Connect to Windows PC", isPresented: $showingConnectInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The Windows desktop interface is ready in preview mode. Live RDP requires a deployed Windows VM and an RDP/WebRTC gateway configured in the cloud backend. No remote host is connected yet.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Desktop").font(.headline)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingMousePad.toggle()
                    showingGamepadStatus = false
                } label: { Image(systemName: "computermouse") }
                .accessibilityLabel("Toggle mouse pad")
                Button {
                    gameControllerMonitor.refreshControllers()
                    showingGamepadStatus.toggle()
                    showingMousePad = false
                } label: { Image(systemName: "gamecontroller") }
                .accessibilityLabel("Gamepad status")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showingMousePad {
                WinlatorMousePadView { _ in }
                    .padding(.trailing, 12)
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if showingGamepadStatus {
                WinlatorGamepadStatusView(monitor: gameControllerMonitor)
                    .padding(12)
                    .frame(maxWidth: 320)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.bottom, 62)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
    }

    private var taskbar: some View {
        HStack(spacing: 16) {
            Button {
                showingStart.toggle()
            } label: {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(showingStart ? .white.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Start menu")

            Button { selectedApp = .browser } label: {
                Image(systemName: "globe").font(.title3).foregroundStyle(.white)
            }
            Button { selectedApp = .vscode } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.title3).foregroundStyle(.white)
            }
            Button { selectedApp = .terminal } label: {
                Image(systemName: "terminal").font(.title3).foregroundStyle(.white)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                    Text(context.date.formatted(date: .numeric, time: .omitted))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
            }
            Image(systemName: "wifi").font(.caption).foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial.opacity(0.85))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5) }
    }

    private var startMenu: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Start", systemImage: "square.grid.3x3.fill").font(.headline)
                Spacer()
                Text("WINLATOR").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text("Search apps, files and settings").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(11)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            Text("PINNED").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach([DesktopApp.thisPC, .browser, .vscode, .ida, .terminal, .recycle]) { app in
                    Button {
                        showingStart = false
                        selectedApp = app
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: app.symbol).font(.title2).foregroundStyle(app.tint)
                            Text(app.rawValue).font(.system(size: 9, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider().overlay(.white.opacity(0.2))
            Button {
                showingStart = false
                showingConnectInfo = true
            } label: {
                Label("Connect to remote Windows PC", systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.15), lineWidth: 1))
    }

    private func appWindow(_ app: DesktopApp) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: app.symbol)
                        .font(.system(size: 32))
                        .foregroundStyle(app.tint)
                        .frame(width: 60, height: 60)
                        .background(app.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.rawValue).font(.title3.bold())
                        Text("Desktop shortcut").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(app.detail).foregroundStyle(.secondary)
                Button {
                    selectedApp = nil
                    showingConnectInfo = true
                } label: {
                    Label("Connect remote PC", systemImage: "network")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                Spacer()
            }
            .padding(22)
            .navigationTitle(app.rawValue)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
