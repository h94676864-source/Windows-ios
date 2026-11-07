import Foundation

enum WinlatorWineRuntimeStorage {
    static func status() -> WinlatorWineRuntimeStatus {
        WinlatorWineRuntimeAdapter.status()
    }
}
