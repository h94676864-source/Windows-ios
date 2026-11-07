import Foundation

struct WinlatorRuntimeReadinessItem: Identifiable {
    let id: String
    let title: String
    let state: String
    let detail: String
    let isReady: Bool
}

struct WinlatorRuntimeReadinessReport {
    let items: [WinlatorRuntimeReadinessItem]
    let environment: WinlatorEnvironmentReport

    var readyCount: Int { items.filter(\\.isReady).count }
    var summary: String {
        let lines = items.map { "\\($0.isReady ? "✓" : "✗") \\($0.title): \\($0.state) — \\($0.detail)" }
        return "Runtime components: \\(readyCount)/\\(items.count) detected\\n"
            + lines.joined(separator: "\\n") + "\\n\\n" + environment.summary
            + "\\n\\nImportant: component detection is not proof that Windows software can execute. A compatible Wine, CPU translation and graphics engine must be bundled and device-tested."
    }
}

/// A single diagnostic snapshot across runtime dependencies and the host device.
enum WinlatorRuntimeReadiness {
    static func inspect(for container: WinlatorContainer) -> WinlatorRuntimeReadinessReport {
        let rootFS: WinlatorRuntimeReadinessItem
        do {
            let context = try WinlatorRootFSRuntimeLoader.prepare(for: container)
            rootFS = WinlatorRuntimeReadinessItem(
                id: "rootfs", title: "ARM64 RootFS", state: "Structurally validated",
                detail: "Shell: /" + context.shellURL.relativePath(from: context.rootURL) + ". Linux execution is not provided by this check.",
                isReady: true
            )
        } catch {
            rootFS = WinlatorRuntimeReadinessItem(
                id: "rootfs", title: "ARM64 RootFS", state: "Not ready",
                detail: error.localizedDescription, isReady: false
            )
        }

        let wineStatus = WinlatorWineRuntimeAdapter.status()
        let wineReady = wineStatus.title == "ARM64 runtime ready"
        let wine = WinlatorRuntimeReadinessItem(
            id: "wine", title: "Wine runtime", state: wineStatus.title,
            detail: wineStatus.detail, isReady: wineReady
        )

        let cpuStatus = WinlatorCPUTranslationRuntimeStorage.status()
        let box64Ready = cpuStatus.box64.title == "ARM64 bundle detected"
        let box86Ready = cpuStatus.box86.title == "ARM64 bundle detected"
        let cpu = WinlatorRuntimeReadinessItem(
            id: "cpu", title: "x86/x64 translation",
            state: box64Ready && box86Ready ? "Frameworks detected" : "Not installed",
            detail: "Box64: \\(cpuStatus.box64.title). Box86: \\(cpuStatus.box86.title). Detection alone does not enable guest instruction translation.",
            isReady: box64Ready && box86Ready
        )

        let graphicsStatus = WinlatorGraphicsRuntimeStorage.status()
        let graphicsReady = graphicsStatus.metal.title == "Available" &&
            graphicsStatus.vulkan.title == "ARM64 bundle detected"
        let graphics = WinlatorRuntimeReadinessItem(
            id: "graphics", title: "Graphics translation",
            state: graphicsReady ? "Components detected" : "Incomplete",
            detail: "Metal: \\(graphicsStatus.metal.title). Vulkan: \\(graphicsStatus.vulkan.title). A callable DirectX translation adapter is still required.",
            isReady: graphicsReady
        )

        return WinlatorRuntimeReadinessReport(
            items: [rootFS, wine, cpu, graphics],
            environment: WinlatorRuntimeEnvironment.inspect(for: container)
        )
    }
}

private extension URL {
    func relativePath(from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let fullPath = standardizedFileURL.path
        guard fullPath.hasPrefix(rootPath + "/") else { return fullPath }
        return String(fullPath.dropFirst(rootPath.count + 1))
    }
}
