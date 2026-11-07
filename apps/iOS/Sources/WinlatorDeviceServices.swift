import AVFoundation
import Foundation
import Network

@MainActor
final class WinlatorDeviceServices: ObservableObject {
    @Published private(set) var audioSessionStatus = "Available"
    @Published private(set) var audioOutput = "Checking…"
    @Published private(set) var audioInput = "Checking…"
    @Published private(set) var networkAvailable = false
    @Published private(set) var networkStatus = "Checking…"
    @Published private(set) var networkType = "Unknown"
    @Published private(set) var isExpensiveNetwork = false
    @Published private(set) var isConstrainedNetwork = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.winlator.ios.network-monitor")

    init() {
        refreshAudioStatus()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.networkAvailable = path.status == .satisfied
                self.networkStatus = path.status == .satisfied ? "Connected" : "Offline"
                if path.usesInterfaceType(.wifi) { self.networkType = "Wi-Fi" }
                else if path.usesInterfaceType(.cellular) { self.networkType = "Cellular" }
                else if path.usesInterfaceType(.wiredEthernet) { self.networkType = "Ethernet" }
                else if path.usesInterfaceType(.loopback) { self.networkType = "Loopback" }
                else { self.networkType = "Other / unavailable" }
                self.isExpensiveNetwork = path.isExpensive
                self.isConstrainedNetwork = path.isConstrained
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func refreshAudioStatus() {
        let session = AVAudioSession.sharedInstance()
        audioSessionStatus = "Ready (iOS audio session)"
        let outputs = session.currentRoute.outputs.map { $0.portName }
        audioOutput = outputs.isEmpty ? "No active output route" : outputs.joined(separator: ", ")
        let inputs = session.currentRoute.inputs.map { $0.portName }
        audioInput = session.isInputAvailable
            ? (inputs.isEmpty ? "Input available" : inputs.joined(separator: ", "))
            : "No input available"
    }

    deinit {
        monitor.cancel()
    }
}
