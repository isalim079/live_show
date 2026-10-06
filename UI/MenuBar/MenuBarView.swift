import SwiftUI
import AppKit

/// Menu Bar dropdown interface adhering strictly to Section 17 of the specification.
public struct MenuBarView: View {
    @ObservedObject var appState: AppState = AppState.shared
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: "sparkles.tv")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 15, weight: .bold))
                Text("liveShow")
                    .font(.headline)
                Spacer()

                if appState.wallpaperManager.userWantsPlay {
                    StatusBadge(text: "Active", color: .green, icon: "play.fill")
                } else {
                    StatusBadge(text: "Paused", color: .orange, icon: "pause.fill")
                }
            }
            .padding(.bottom, 2)

            Divider()

            // Quick Playback Controls
            HStack(spacing: 8) {
                Button(action: {
                    appState.togglePlayPause()
                }) {
                    Label(
                        appState.wallpaperManager.userWantsPlay ? "Pause" : "Resume",
                        systemImage: appState.wallpaperManager.userWantsPlay ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.wallpaperManager.userWantsPlay ? .secondary : .accentColor)

                Button(action: {
                    appState.toggleMute()
                }) {
                    Image(systemName: appState.store.settings.muteByDefault ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 32)
                }
                .buttonStyle(.bordered)
            }

            // Displays overview
            VStack(alignment: .leading, spacing: 6) {
                Text("Displays")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(appState.displayManager.displays) { display in
                    HStack {
                        Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                            .foregroundColor(.secondary)
                        Text(display.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()

                        if let assignment = appState.store.assignments[display.id],
                           let wp = appState.store.wallpapers.first(where: { $0.id == assignment.wallpaperID }) {
                            Text(wp.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.accentColor)
                                .lineLimit(1)
                        } else {
                            Text("None")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            // Launch at Mac Startup Toggle
            Toggle(isOn: Binding(
                get: { appState.loginItemManager.isEnabled },
                set: { newValue in
                    try? appState.loginItemManager.setEnabled(newValue)
                    var s = appState.store.settings
                    s.launchAtLogin = newValue
                    appState.store.settings = s
                }
            )) {
                HStack(spacing: 6) {
                    Image(systemName: "macwindow.badge.plus")
                        .foregroundColor(.secondary)
                    Text("Start on Mac Boot")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            Divider()

            // Navigation Links
            VStack(spacing: 4) {
                Button(action: {
                    WindowManager.shared.openLibrary()
                }) {
                    HStack {
                        Label("Wallpaper Library", systemImage: "photo.stack")
                        Spacer()
                        Text("⌘L").font(.caption).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)

                Button(action: {
                    WindowManager.shared.openSettings()
                }) {
                    HStack {
                        Label("Settings...", systemImage: "gearshape")
                        Spacer()
                        Text("⌘,").font(.caption).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)

                Button(action: {
                    WindowManager.shared.openDiagnostics()
                }) {
                    HStack {
                        Label("System Diagnostics", systemImage: "stethoscope")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }

            Divider()

            // Quit
            Button(action: {
                NSApp.terminate(nil)
            }) {
                HStack {
                    Label("Quit LiveWallpaper", systemImage: "power")
                    Spacer()
                    Text("⌘Q").font(.caption).foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .padding(.vertical, 2)
        }
        .padding(14)
        .frame(width: 290)
    }
}
