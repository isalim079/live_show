import Foundation
import AppKit
import Combine

/// Root application state coordinator.
/// Adheres to Section 4 and Section 21 of the specification.
@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    public let store: WallpaperStore
    public let displayManager: DisplayManager
    public let powerMonitor: PowerStateMonitor
    public let sleepMonitor: SleepWakeMonitor
    public let workspaceMonitor: WorkspaceMonitor
    public let loginItemManager: LoginItemManager
    public let wallpaperManager: WallpaperManager

    @Published public var selectedTab: Int = 0
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let store = WallpaperStore()
        let displayManager = DisplayManager()
        let powerMonitor = PowerStateMonitor()
        let sleepMonitor = SleepWakeMonitor()
        let workspaceMonitor = WorkspaceMonitor()
        let loginItemManager = LoginItemManager()

        let wallpaperManager = WallpaperManager(
            displayManager: displayManager,
            powerMonitor: powerMonitor,
            sleepMonitor: sleepMonitor,
            workspaceMonitor: workspaceMonitor
        )

        self.store = store
        self.displayManager = displayManager
        self.powerMonitor = powerMonitor
        self.sleepMonitor = sleepMonitor
        self.workspaceMonitor = workspaceMonitor
        self.loginItemManager = loginItemManager
        self.wallpaperManager = wallpaperManager

        wireDependencies()
        ScreenSaverManager.shared.installScreenSaver()
    }

    private func wireDependencies() {
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        wallpaperManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        displayManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        wallpaperManager.wallpaperResolver = { [weak self] id in
            guard let self = self,
                  let wallpaper = self.store.wallpapers.first(where: { $0.id == id }),
                  let resolvedURL = self.store.resolveURL(for: wallpaper) else {
                return nil
            }
            return (wallpaper, resolvedURL)
        }

        wallpaperManager.assignmentProvider = { [weak self] displayID in
            guard let self = self else { return nil }
            let name = self.displayManager.screen(for: displayID)?.localizedName
            return self.store.assignment(for: displayID, displayName: name)
        }

        wallpaperManager.settingsProvider = { [weak self] in
            self?.store.settings ?? .default
        }
    }

    /// Boots the application and restores active wallpapers.
    public func start() {
        AppLogger.app.info("LiveWallpaper starting up...")
        displayManager.refreshDisplays()

        // Ensure connected displays have their assignments resolved and recorded
        for display in displayManager.displays {
            if let assignment = store.assignment(for: display.id, displayName: display.name) {
                if store.assignments[display.id] == nil {
                    store.setAssignment(
                        wallpaperID: assignment.wallpaperID,
                        forDisplayID: display.id,
                        displayName: display.name,
                        scalingMode: assignment.scalingMode
                    )
                }
            }
        }

        if store.assignments.isEmpty, let firstWallpaper = store.wallpapers.first {
            setWallpaperForAllDisplays(firstWallpaper, scalingMode: store.settings.defaultScalingMode)
        }

        wallpaperManager.reconcile()

        if store.settings.autoStartPlayback {
            wallpaperManager.userWantsPlay = true
        }

        wallpaperManager.reevaluatePolicy()

        // Sync system wallpaper for all connected displays
        for display in displayManager.displays {
            if let assignment = store.assignment(for: display.id, displayName: display.name),
               let (wallpaper, url) = wallpaperManager.wallpaperResolver?(assignment.wallpaperID),
               let screen = displayManager.screen(for: display.id) {
                SystemWallpaperSynchronizer.shared.sync(wallpaper: wallpaper, videoURL: url, for: screen)
            }
        }

        // Secondary reconciliation for display settling after system startup/wake
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            self.displayManager.refreshDisplays()
            self.wallpaperManager.reconcile()
        }
    }

    public func togglePlayPause() {
        wallpaperManager.userWantsPlay.toggle()
    }

    public func setWallpaper(_ wallpaper: Wallpaper, forDisplayID displayID: String, scalingMode: ScalingMode = .fill) {
        guard let resolvedURL = store.resolveURL(for: wallpaper) else {
            AppLogger.wallpaper.error("Cannot resolve URL for wallpaper \(wallpaper.title)")
            return
        }

        let displayName = displayManager.displays.first(where: { $0.id == displayID })?.name ?? "Display \(displayID)"
        store.setAssignment(wallpaperID: wallpaper.id, forDisplayID: displayID, displayName: displayName, scalingMode: scalingMode)
        wallpaperManager.assignWallpaper(wallpaper, resolvedURL: resolvedURL, toDisplayID: displayID, scalingMode: scalingMode)

        if let screen = displayManager.screen(for: displayID) {
            SystemWallpaperSynchronizer.shared.sync(wallpaper: wallpaper, videoURL: resolvedURL, for: screen)
        }
    }

    public func setWallpaperForAllDisplays(_ wallpaper: Wallpaper, scalingMode: ScalingMode = .fill) {
        guard let resolvedURL = store.resolveURL(for: wallpaper) else {
            AppLogger.wallpaper.error("Cannot resolve URL for wallpaper \(wallpaper.title)")
            return
        }

        for display in displayManager.displays {
            store.setAssignment(wallpaperID: wallpaper.id, forDisplayID: display.id, displayName: display.name, scalingMode: scalingMode)
        }
        wallpaperManager.assignWallpaperToAllDisplays(wallpaper, resolvedURL: resolvedURL, scalingMode: scalingMode)
        SystemWallpaperSynchronizer.shared.syncAllScreens(wallpaper: wallpaper, videoURL: resolvedURL)
    }

    public func toggleMute() {
        var settings = store.settings
        settings.muteByDefault.toggle()
        store.settings = settings
        wallpaperManager.updatePlaybackSettings(settings)
    }

    public func setVolume(_ volume: Float) {
        var settings = store.settings
        settings.volume = volume
        if volume > 0 {
            settings.muteByDefault = false
        }
        store.settings = settings
        wallpaperManager.updatePlaybackSettings(settings)
    }
}
