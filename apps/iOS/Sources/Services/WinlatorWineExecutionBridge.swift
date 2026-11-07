import Foundation

/// Routes installer launches through validated RootFS, prefix and Wine prerequisites.
/// No subprocess or shell execution is attempted by the iOS app itself.
enum WinlatorWineExecutionBridge {
    static func launch(executableURL: URL, container: WinlatorContainer) -> String {
        let report = WinlatorWineLaunchPreflight.inspect(
            executableURL: executableURL, container: container
        )
        guard report.canSubmitToRuntime else {
            return "Launch preflight failed:\n" + report.message
        }
        return WinlatorWineRuntimeAdapter.launch(executableURL: executableURL, container: container)
    }
}
