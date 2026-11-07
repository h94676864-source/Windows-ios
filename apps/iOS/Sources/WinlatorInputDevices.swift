import SwiftUI
import GameController
import Combine

final class WinlatorGameControllerMonitor: ObservableObject {
    @Published private(set) var connectedCount = 0
    @Published private(set) var lastInput = "No controller input"
    @Published private(set) var controllerNames: [String] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in self?.refreshControllers() })
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.refreshControllers() })
        refreshControllers()
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    func refreshControllers() {
        let controllers = GCController.controllers()
        connectedCount = controllers.count
        controllerNames = controllers.map { $0.vendorName ?? "Game Controller" }
        for controller in controllers {
            controller.extendedGamepad?.valueChangedHandler = { [weak self] _, element in
                DispatchQueue.main.async { self?.lastInput = String(describing: element) }
            }
            controller.microGamepad?.valueChangedHandler = { [weak self] _, element in
                DispatchQueue.main.async { self?.lastInput = String(describing: element) }
            }
        }
    }
}

struct WinlatorMousePadView: View {
    @State private var cursorOffset: CGSize = .zero
    @State private var dragOrigin: CGSize = .zero
    @State private var lastAction = "Move cursor"
    let onMouseEvent: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("MOUSE", systemImage: "computermouse").font(.system(size: 10, weight: .bold))
                Spacer()
                Text(lastAction).font(.system(size: 9)).lineLimit(1)
            }.foregroundStyle(.white)
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.38))
                    RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.22), lineWidth: 1)
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .position(x: min(max(18, proxy.size.width / 2 + cursorOffset.width), proxy.size.width - 18),
                                  y: min(max(18, proxy.size.height / 2 + cursorOffset.height), proxy.size.height - 18))
                }
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        cursorOffset = CGSize(width: dragOrigin.width + value.translation.width,
                                              height: dragOrigin.height + value.translation.height)
                        lastAction = "Moving"
                        onMouseEvent("move:\(value.translation.width.rounded()),\(value.translation.height.rounded())")
                    }
                    .onEnded { value in
                        dragOrigin = cursorOffset
                        lastAction = "Moved"
                        onMouseEvent("move-end:\(value.translation.width.rounded()),\(value.translation.height.rounded())")
                    })
            }.frame(height: 108)
            HStack(spacing: 10) {
                Button { lastAction = "Left click"; onMouseEvent("left-click") } label: {
                    Label("Left", systemImage: "cursorarrow.click").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Button { lastAction = "Right click"; onMouseEvent("right-click") } label: {
                    Label("Right", systemImage: "cursorarrow.rays").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }.tint(.white)
        }
        .padding(12).frame(width: 250)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.18), lineWidth: 1))
    }
}

struct WinlatorGamepadStatusView: View {
    @ObservedObject var monitor: WinlatorGameControllerMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gamecontroller.fill")
                Text("Gamepad").font(.headline)
                Spacer()
                Circle().fill(monitor.connectedCount > 0 ? Color.green : Color.orange).frame(width: 8, height: 8)
            }
            Text(monitor.connectedCount > 0 ? "\(monitor.connectedCount) controller(s) connected" : "No controller connected")
                .font(.subheadline)
            ForEach(Array(monitor.controllerNames.enumerated()), id: \.offset) { _, name in
                Text(name).font(.caption).foregroundStyle(.secondary)
            }
            Text("Last input: \(monitor.lastInput)").font(.caption2).foregroundStyle(.secondary)
            Text("Detection is active; Windows input forwarding requires the runtime adapter.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
