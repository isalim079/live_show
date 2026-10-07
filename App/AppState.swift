import Foundation
import AppKit
import Combine

public struct BootTimeline: Sendable {
    public let t0Launch: Date
    public var tScreens: Date?
    public var screensCount: Int = 0
    public var tPlay: Date?
    public var firstPlayingDisplay: String?

    public var secondsToFirstScreens: Double? {
        guard let tScreens else { return nil }
        return tScreens.timeIntervalSince(t0Launch)
    }

    public var secondsToFirstFrame: Double? {
        guard let tPlay else { return nil }
        return tPlay.timeIntervalSince(t0Launch)
    }
}

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
    @Published public private(set) var bootTimeline: BootTimeline?
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
        // Install or repair .saver when missing / codesign-invalid (silent lock-screen failures).
        ScreenSaverManager.shared.ensureInstalled()
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
                ?? self.displayManager.displays.first(where: { $0.id == displayID })?.name
            return self.store.assignment(for: displayID, displayName: name)
        }

        wallpaperManager.settingsProvider = { [weak self] in
            self?.store.settings ?? .default
        }

        wallpaperManager.assignmentSyncHandler = { [weak self] in
            self?.syncDisplayAssignments()
        }

        wallpaperManager.onSessionStateChanged = { [weak self] session, state in
            guard let self = self else { return }
            if case .playing = state {
                if self.bootTimeline?.tPlay == nil {
                    self.bootTimeline?.tPlay = Date()
                    self.bootTimeline?.firstPlayingDisplay = session.display.name
                    let secs = self.bootTimeline?.secondsToFirstFrame ?? 0
                    AppLogger.diagnostics.info("Boot timeline: first frame playing on \(session.display.name) in \(String(format: "%.2f", secs))s")
                    AppLogger.diagnosticBuffer.log(
                        category: "boot",
                        message: "First frame playing on \(session.display.name) in \(String(format: "%.2f", secs))s"
                    )
                }
            }
        }
    }

    /// Re-persists assignments under current display IDs after wake remaps.
    private func syncDisplayAssignments() {
        for display in displayManager.displays {
            if let assignment = store.assignment(for: display.id, displayName: display.name) {
                if store.assignments[display.id] == nil
                    || store.assignments[display.id]?.wallpaperID != assignment.wallpaperID
                    || store.assignments[display.id]?.displayName != display.name {
                    store.setAssignment(
                        wallpaperID: assignment.wallpaperID,
                        forDisplayID: display.id,
                        displayName: display.name,
                        scalingMode: assignment.scalingMode
                    )
                }
            }
        }
    }

    /// Boots the application and restores active wallpapers.
    public func start() {
        let launchTime = Date()
        var timeline = BootTimeline(t0Launch: launchTime)
        AppLogger.app.info("LiveWallpaper starting up...")
        AppLogger.diagnostics.info("Boot timeline: t0 launch recorded at \(launchTime)")
        AppLogger.diagnosticBuffer.log(category: "boot", message: "t0 launch at \(launchTime)")

        // Sync Login Item status with settings
        loginItemManager.checkStatus()
        var settings = store.settings
        if settings.launchAtLogin != loginItemManager.isEnabled {
            settings.launchAtLogin = loginItemManager.isEnabled
            store.settings = settings
        }

        self.displayManager.refreshDisplays()
        if !self.displayManager.displays.isEmpty {
            timeline.tScreens = Date()
            timeline.screensCount = self.displayManager.displays.count
            let secScreens = timeline.secondsToFirstScreens ?? 0
            AppLogger.diagnostics.info("Boot timeline: t_screens reached (\(self.displayManager.displays.count) screens) in \(String(format: "%.2f", secScreens))s")
            AppLogger.diagnosticBuffer.log(category: "boot", message: "t_screens (\(self.displayManager.displays.count) screens) in \(String(format: "%.2f", secScreens))s")
        }
        self.bootTimeline = timeline

        // Ensure connected displays have their assignments resolved and recorded
        syncDisplayAssignments()

        if store.assignments.isEmpty, let firstWallpaper = store.wallpapers.first {
            setWallpaperForAllDisplays(firstWallpaper, scalingMode: store.settings.defaultScalingMode)
        }

        wallpaperManager.reconcile()

        if store.settings.autoStartPlayback {
            wallpaperManager.userWantsPlay = true
        }

        wallpaperManager.reevaluatePolicy()

        // Sync system static frames + native Aerial lock-screen asset for the primary wallpaper.
        var primary: (Wallpaper, URL)?
        for display in displayManager.displays {
            if let assignment = store.assignment(for: display.id, displayName: display.name),
               let (wallpaper, url) = wallpaperManager.wallpaperResolver?(assignment.wallpaperID),
               let screen = displayManager.screen(for: display.id) {
                SystemWallpaperSynchronizer.shared.sync(wallpaper: wallpaper, videoURL: url, for: screen)
                if primary == nil { primary = (wallpaper, url) }
            }
        }
        if let (wallpaper, url) = primary {
            Task { await self.syncLockScreen(wallpaper: wallpaper, videoURL: url) }
        } else {
            ScreenSaverManager.shared.refreshReadiness()
        }

        // Shared boot multi-pass recovery (0s / 1.5s / 3.0s / 8.0s)
        wallpaperManager.recoverSessions(reason: .boot)
        ScreenSaverManager.shared.refreshReadiness()
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
        Task { await self.syncLockScreen(wallpaper: wallpaper, videoURL: resolvedURL) }
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
        Task { await self.syncLockScreen(wallpaper: wallpaper, videoURL: resolvedURL) }
    }

    /// Encodes HEVC Aerial with visible progress, then refreshes Desktop+Idle diagnostics.
    private func syncLockScreen(wallpaper: Wallpaper, videoURL: URL) async {
        let ok = await ScreenSaverManager.shared.performLockScreenSync(
            videoURL: videoURL,
            wallpaperID: wallpaper.id,
            title: wallpaper.title
        )
        if AerialLockScreenInstaller.isSupported && !ok {
            AppLogger.wallpaper.error("Lock screen Aerial sync failed for \(wallpaper.title)")
        }
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
