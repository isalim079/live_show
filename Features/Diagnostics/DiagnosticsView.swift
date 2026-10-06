import SwiftUI
import AppKit

/// Diagnostics screen displaying system telemetry, display topology, and playback logs.
/// Adheres strictly to Section 37 of the specification.
public struct DiagnosticsView: View {
    @ObservedObject var appState: AppState = AppState.shared
    @ObservedObject private var screenSaverManager = ScreenSaverManager.shared
    @State private var copied: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "stethoscope")
                    .foregroundColor(.accentColor)
                    .font(.title2)
                Text("System Diagnostics")
                    .font(.title2.bold())
                Spacer()

                Button(action: copyDiagnosticsReport) {
                    Label(copied ? "Copied!" : "Copy Report", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.regularMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // System Information
                    diagnosticSection(title: "Environment") {
                        diagnosticRow(label: "macOS Version", value: ProcessInfo.processInfo.operatingSystemVersionString)
                        diagnosticRow(label: "Architecture", value: systemArchitecture)
                        diagnosticRow(label: "App Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        diagnosticRow(label: "Power Source", value: "\(appState.powerMonitor.powerSource.rawValue) (\(appState.powerMonitor.batteryLevel.map { "\($0)%" } ?? "N/A"))")
                    }

                    diagnosticSection(title: "Power / Lock State") {
                        diagnosticRow(label: "Screen locked", value: appState.sleepMonitor.isScreenLocked ? "YES" : "no")
                        diagnosticRow(label: "Screens asleep", value: appState.sleepMonitor.areScreensAsleep ? "YES" : "no")
                        diagnosticRow(label: "System asleep", value: appState.sleepMonitor.isSystemAsleep ? "YES" : "no")
                        diagnosticRow(
                            label: "Displays vs sessions",
                            value: "\(appState.displayManager.displays.count) / \(appState.wallpaperManager.activeSessions.count)"
                        )
                    }

                    // Lock Screen readiness (Desktop+Idle Aerial on macOS 27)
                    diagnosticSection(title: "Lock Screen (\(lockScreenSummary))") {
                        let r = screenSaverManager.readiness
                        diagnosticRow(label: "Pipeline", value: (r?.usesAerialPipeline ?? AerialLockScreenInstaller.isSupported) ? "Desktop+Idle Aerial" : "Screen Saver")
                        if r?.usesAerialPipeline == true {
                            diagnosticRow(label: "Aerial asset", value: boolLabel(r?.aerialAssetPresent ?? false))
                            diagnosticRow(label: "Aerial video", value: boolLabel(r?.aerialVideoPresent ?? false))
                            diagnosticRow(label: "Desktop aerial", value: slotLabel(ok: r?.desktopProviderOK == true && r?.desktopAssetOK == true))
                            diagnosticRow(label: "Idle aerial", value: slotLabel(ok: r?.idleProviderOK == true && r?.idleAssetOK == true))
                            diagnosticRow(label: "Asset ID", value: r?.aerialAssetID ?? "—")
                        } else {
                            diagnosticRow(label: ".saver installed", value: boolLabel(r?.saverInstalled ?? screenSaverManager.isInstalled))
                            diagnosticRow(label: "Codesign", value: codesignLabel(r))
                            diagnosticRow(label: "Idle provider", value: idleLabel(r))
                        }
                        diagnosticRow(label: "Detail", value: r?.idleDetail ?? "—")

                        if !screenSaverManager.lockScreenJobMessage.isEmpty {
                            HStack(spacing: 8) {
                                if screenSaverManager.lockScreenJobPhase.isRunning {
                                    ProgressView().controlSize(.small)
                                }
                                Text(screenSaverManager.lockScreenJobMessage)
                                    .font(.caption)
                                    .foregroundColor(screenSaverManager.lockScreenJobPhase == .failed ? .red : .secondary)
                            }
                        }

                        HStack(spacing: 10) {
                            Button(action: repairLockScreen) {
                                if screenSaverManager.lockScreenJobPhase.isRunning {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Working…")
                                } else {
                                    Label("Repair Lock Screen Integration", systemImage: "wrench.and.screwdriver")
                                }
                            }
                            .disabled(screenSaverManager.lockScreenJobPhase.isRunning)
                            .buttonStyle(.borderedProminent)

                            Button("Refresh") {
                                screenSaverManager.refreshReadiness()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    }

                    // Connected Displays
                    diagnosticSection(title: "Connected Displays (\(appState.displayManager.displays.count))") {
                        ForEach(appState.displayManager.displays) { display in
                            diagnosticRow(label: display.name, value: "\(Int(display.frame.width))x\(Int(display.frame.height)) @ \(Int(round(display.refreshRate)))Hz (\(display.isBuiltIn ? "Built-in" : "External"))")
                        }
                    }

                    // Active Wallpaper Sessions
                    diagnosticSection(title: "Active Sessions (\(appState.wallpaperManager.activeSessions.count))") {
                        if appState.wallpaperManager.activeSessions.isEmpty {
                            Text("No active playback sessions.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(appState.wallpaperManager.activeSessions.values), id: \.displayID) { session in
                                diagnosticRow(
                                    label: session.display.name,
                                    value: "\(session.currentWallpaper?.title ?? "None") • \(session.playbackState.label)"
                                )
                            }
                        }
                    }

                    // Recent Diagnostic Logs
                    diagnosticSection(title: "Recent Event Log") {
                        let entries = AppLogger.diagnosticBuffer.getEntries()
                        if entries.isEmpty {
                            Text("No log events recorded.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(entries.suffix(15)) { entry in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("[\(entry.category)]")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.accentColor)
                                        Text(entry.message)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 560, minHeight: 450)
        .onAppear {
            screenSaverManager.refreshReadiness()
        }
    }

    private var lockScreenSummary: String {
        screenSaverManager.readiness?.summary ?? "Checking…"
    }

    private func boolLabel(_ value: Bool) -> String {
        value ? "OK" : "Missing"
    }

    private func codesignLabel(_ r: LockScreenReadiness?) -> String {
        guard let r else { return screenSaverManager.lastCodesignDetail }
        return r.codesignOK ? "OK — \(r.codesignDetail)" : "FAIL — \(r.codesignDetail)"
    }

    private func idleLabel(_ r: LockScreenReadiness?) -> String {
        guard let r else { return "Unknown" }
        if r.idleProviderOK && r.idleAssetOK { return "OK — \(r.idleDetail)" }
        return "FAIL — \(r.idleDetail)"
    }

    private func slotLabel(ok: Bool) -> String {
        ok ? "OK" : "FAIL"
    }

    private func repairLockScreen() {
        Task {
            _ = ScreenSaverManager.shared.repairLockScreenIntegration()
            guard let assignment = appState.store.assignments.values.first,
                  let (wallpaper, url) = appState.wallpaperManager.wallpaperResolver?(assignment.wallpaperID) else {
                ScreenSaverManager.shared.updateLockScreenJob(
                    phase: .failed,
                    message: "Failed: no active wallpaper to sync"
                )
                return
            }
            _ = await ScreenSaverManager.shared.performLockScreenSync(
                videoURL: url,
                wallpaperID: wallpaper.id,
                title: wallpaper.title
            )
        }
    }

    private func diagnosticSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
        }
    }

    private func diagnosticRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
    }

    private var systemArchitecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }

    private func copyDiagnosticsReport() {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let displays = appState.displayManager.displays.map { "- \($0.detailedDescription)" }.joined(separator: "\n")
        let sessions = appState.wallpaperManager.activeSessions.values.map { "- \($0.display.name): \($0.currentWallpaper?.title ?? "None") (\($0.playbackState.label))" }.joined(separator: "\n")
        let power = "\(appState.powerMonitor.powerSource.rawValue) (\(appState.powerMonitor.batteryLevel.map { "\($0)%" } ?? "N/A"))"
        let sleep = """
        screenLocked=\(appState.sleepMonitor.isScreenLocked)
        screensAsleep=\(appState.sleepMonitor.areScreensAsleep)
        systemAsleep=\(appState.sleepMonitor.isSystemAsleep)
        displays/sessions=\(appState.displayManager.displays.count)/\(appState.wallpaperManager.activeSessions.count)
        """

        let r = screenSaverManager.readiness
        let lockScreen = """
        Pipeline: \(r.map { $0.usesAerialPipeline ? "Desktop+Idle Aerial" : "ScreenSaver" } ?? "?")
        Aerial asset: \(r.map { String($0.aerialAssetPresent) } ?? "?") video=\(r.map { String($0.aerialVideoPresent) } ?? "?") id=\(r?.aerialAssetID ?? "—")
        Desktop aerial: \(r.map { String($0.desktopProviderOK && $0.desktopAssetOK) } ?? "?")
        Idle aerial: \(r.map { String($0.idleProviderOK && $0.idleAssetOK) } ?? "?")
        Detail: \(r?.idleDetail ?? "unchecked")
        Job: \(screenSaverManager.lockScreenJobPhase.rawValue) — \(screenSaverManager.lockScreenJobMessage)
        Saver: \(r.map { String($0.saverInstalled) } ?? "?") codesign=\(r?.codesignDetail ?? screenSaverManager.lastCodesignDetail)
        Ready: \(r.map { String($0.isReady) } ?? "?")
        """

        let report = """
        # LiveWallpaper Diagnostic Report
        Generated: \(Date())
        macOS: \(os)
        Architecture: \(systemArchitecture)
        Power: \(power)

        ## Power / Lock State
        \(sleep)

        ## Lock Screen
        \(lockScreen)

        ## Displays
        \(displays.isEmpty ? "None" : displays)

        ## Active Sessions
        \(sessions.isEmpty ? "None" : sessions)
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)

        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
