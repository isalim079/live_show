import SwiftUI
import AppKit

/// Diagnostics screen displaying system telemetry, display topology, and playback logs.
/// Adheres strictly to Section 37 of the specification.
public struct DiagnosticsView: View {
    @ObservedObject var appState: AppState = AppState.shared
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

        let report = """
        # LiveWallpaper Diagnostic Report
        Generated: \(Date())
        macOS: \(os)
        Architecture: \(systemArchitecture)
        Power: \(power)

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
