import SwiftUI
import ServiceManagement

/// Application Preferences and Settings window.
/// Strictly implements Section 18 of the specification.
public struct SettingsView: View {
    @ObservedObject var appState: AppState = AppState.shared
    @ObservedObject private var screenSaverManager = ScreenSaverManager.shared
    @State private var launchAtLoginError: String? = nil

    public init() {}

    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            playbackTab
                .tabItem {
                    Label("Playback", systemImage: "play.circle")
                }

            powerTab
                .tabItem {
                    Label("Power & System", systemImage: "battery.100.bolt")
                }
        }
        .padding(20)
        .frame(width: 480, height: 400)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { appState.loginItemManager.isEnabled },
                    set: { newValue in
                        do {
                            try appState.loginItemManager.setEnabled(newValue)
                            var s = appState.store.settings
                            s.launchAtLogin = newValue
                            appState.store.settings = s
                        } catch {
                            launchAtLoginError = error.localizedDescription
                        }
                    }
                ))

                if let err = launchAtLoginError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Toggle("Start wallpaper playback automatically on launch", isOn: Binding(
                    get: { appState.store.settings.autoStartPlayback },
                    set: {
                        var s = appState.store.settings
                        s.autoStartPlayback = $0
                        appState.store.settings = s
                    }
                ))
            } header: {
                Text("Startup")
            }

            Section {
                Button(action: {
                    ScreenSaverManager.shared.openScreenSaverSettings()
                }) {
                    HStack {
                        Label("Open macOS Screen Saver & Lock Screen Settings", systemImage: "sparkles.tv")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: repairLockScreen) {
                    Label("Repair Lock Screen Integration", systemImage: "wrench.and.screwdriver")
                }
                .disabled(screenSaverManager.lockScreenJobPhase.isRunning)

                if screenSaverManager.lockScreenJobPhase.isRunning
                    || screenSaverManager.lockScreenJobPhase == .done
                    || screenSaverManager.lockScreenJobPhase == .failed
                    || !screenSaverManager.lockScreenJobMessage.isEmpty {
                    HStack(spacing: 8) {
                        if screenSaverManager.lockScreenJobPhase.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else if screenSaverManager.lockScreenJobPhase == .done {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else if screenSaverManager.lockScreenJobPhase == .failed {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        Text(screenSaverManager.lockScreenJobMessage.isEmpty
                             ? statusPlaceholder
                             : screenSaverManager.lockScreenJobMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Lock Screen & System Integration")
            } footer: {
                Text("On macOS 27 Golden Gate, Live Show sets a native Aerial wallpaper for Desktop+Idle (like Wallper). Encoding can take 30–90 seconds — watch the status above. “Pause when screen is locked” only affects the desktop window, not Lock Screen video.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var statusPlaceholder: String {
        screenSaverManager.lockScreenJobPhase.isRunning ? "Working…" : ""
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

    private var playbackTab: some View {
        Form {
            Section {
                Toggle("Loop video seamlessly", isOn: Binding(
                    get: { appState.store.settings.loopVideo },
                    set: {
                        var s = appState.store.settings
                        s.loopVideo = $0
                        appState.store.settings = s
                    }
                ))

                Toggle("Mute audio by default", isOn: Binding(
                    get: { appState.store.settings.muteByDefault },
                    set: {
                        var s = appState.store.settings
                        s.muteByDefault = $0
                        appState.store.settings = s
                        appState.wallpaperManager.updatePlaybackSettings(s)
                    }
                ))

                Picker("Default Scaling Mode", selection: Binding(
                    get: { appState.store.settings.defaultScalingMode },
                    set: {
                        var s = appState.store.settings
                        s.defaultScalingMode = $0
                        appState.store.settings = s
                    }
                )) {
                    ForEach(ScalingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Playback Speed", selection: Binding(
                    get: { appState.store.settings.playbackSpeed },
                    set: {
                        var s = appState.store.settings
                        s.playbackSpeed = $0
                        appState.store.settings = s
                        appState.wallpaperManager.updatePlaybackSettings(s)
                    }
                )) {
                    Text("0.5x").tag(Float(0.5))
                    Text("0.75x").tag(Float(0.75))
                    Text("1.0x (Normal)").tag(Float(1.0))
                    Text("1.25x").tag(Float(1.25))
                    Text("1.5x").tag(Float(1.5))
                    Text("2.0x").tag(Float(2.0))
                }
            } header: {
                Text("Video Engine")
            }
        }
        .formStyle(.grouped)
    }

    private var powerTab: some View {
        Form {
            Section {
                Toggle("Pause playback when running on battery", isOn: Binding(
                    get: { appState.store.settings.pauseOnBattery },
                    set: {
                        var s = appState.store.settings
                        s.pauseOnBattery = $0
                        appState.store.settings = s
                        appState.wallpaperManager.reevaluatePolicy()
                    }
                ))

                Toggle("Pause playback when displays sleep", isOn: Binding(
                    get: { appState.store.settings.pauseWhenDisplaySleeps },
                    set: {
                        var s = appState.store.settings
                        s.pauseWhenDisplaySleeps = $0
                        appState.store.settings = s
                        appState.wallpaperManager.reevaluatePolicy()
                    }
                ))

                Toggle("Pause playback when screen is locked", isOn: Binding(
                    get: { appState.store.settings.pauseWhenScreenLocked },
                    set: {
                        var s = appState.store.settings
                        s.pauseWhenScreenLocked = $0
                        appState.store.settings = s
                        appState.wallpaperManager.reevaluatePolicy()
                    }
                ))

                Toggle("Pause playback when a fullscreen app is active", isOn: Binding(
                    get: { appState.store.settings.pauseOnFullscreen },
                    set: {
                        var s = appState.store.settings
                        s.pauseOnFullscreen = $0
                        appState.store.settings = s
                        appState.wallpaperManager.reevaluatePolicy()
                    }
                ))
            } header: {
                Text("Energy & Workspaces")
            } footer: {
                Text("Pausing live wallpapers during screen sleep, lock, or battery power reduces power consumption and extends battery life.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
