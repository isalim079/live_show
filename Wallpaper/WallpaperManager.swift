import Foundation
import AppKit
import Combine

/// Central coordinator for wallpaper playback across all connected displays.
/// Implements Section 4 and Section 8 of the specification.
@MainActor
public final class WallpaperManager: ObservableObject, DisplayManagerDelegate, WallpaperSessionDelegate {
    @Published public private(set) var activeSessions: [String: WallpaperSession] = [:]
    @Published public var userWantsPlay: Bool = true {
        didSet { reevaluatePolicy() }
    }

    private let displayManager: DisplayManager
    private let powerMonitor: PowerStateMonitor
    private let sleepMonitor: SleepWakeMonitor
    private let workspaceMonitor: WorkspaceMonitor
    private var cancellables = Set<AnyCancellable>()

    // Injected repository / store closure
    public var wallpaperResolver: ((UUID) -> (Wallpaper, URL)?)?
    public var assignmentProvider: ((String) -> WallpaperAssignment?)?
    public var settingsProvider: (() -> LiveWallpaperSettings)?

    public init(
        displayManager: DisplayManager,
        powerMonitor: PowerStateMonitor,
        sleepMonitor: SleepWakeMonitor,
        workspaceMonitor: WorkspaceMonitor
    ) {
        self.displayManager = displayManager
        self.powerMonitor = powerMonitor
        self.sleepMonitor = sleepMonitor
        self.workspaceMonitor = workspaceMonitor

        self.displayManager.delegate = self
        setupSystemSubscribers()
    }

    private func setupSystemSubscribers() {
        powerMonitor.$powerSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reevaluatePolicy() }
            .store(in: &cancellables)

        sleepMonitor.onStateChange = { [weak self] in
            self?.reevaluatePolicy()
        }

        workspaceMonitor.onFullscreenStateChanged = { [weak self] _ in
            self?.reevaluatePolicy()
        }
    }

    /// Evaluates central policy and applies it to every active session.
    public func reevaluatePolicy() {
        let settings = settingsProvider?() ?? .default

        let input = WallpaperPolicy.Input(
            userWantsPlay: userWantsPlay,
            isSystemAsleep: sleepMonitor.isSystemAsleep,
            areScreensAsleep: sleepMonitor.areScreensAsleep,
            isScreenLocked: sleepMonitor.isScreenLocked,
            powerSource: powerMonitor.powerSource,
            isFullscreenAppActive: workspaceMonitor.isFullscreenAppActive,
            settings: settings
        )

        let action = WallpaperPolicy.evaluate(input: input)
        AppLogger.wallpaper.info("Policy evaluated action: \(String(describing: action))")

        for (_, session) in activeSessions {
            session.applyPolicy(action: action)
        }
    }

    /// Reconciles all display sessions with connected hardware and assignments.
    public func reconcile() {
        let currentDisplays = displayManager.displays

        // 1. Destroy sessions for displays that were disconnected
        let currentIDs = Set(currentDisplays.map { $0.id })
        for (id, session) in activeSessions where !currentIDs.contains(id) {
            AppLogger.wallpaper.info("Tearing down session for disconnected display \(id)")
            session.destroy()
            activeSessions.removeValue(forKey: id)
        }

        // 2. Create or verify sessions for active displays
        for display in currentDisplays {
            if let existingSession = activeSessions[display.id] {
                if let screen = displayManager.screen(for: display.id) {
                    existingSession.updateGeometry(screen: screen, descriptor: display)
                }
            } else {
                createSession(for: display)
            }
        }

        reevaluatePolicy()
    }

    private func createSession(for display: DisplayDescriptor) {
        guard let screen = displayManager.screen(for: display.id) else {
            AppLogger.wallpaper.warning("Could not find NSScreen for display ID \(display.id)")
            return
        }

        let session = WallpaperSession(screen: screen, display: display)
        session.delegate = self
        activeSessions[display.id] = session

        // Apply settings
        let settings = settingsProvider?() ?? .default
        session.setMuted(settings.muteByDefault)
        session.setVolume(settings.volume)
        session.setPlaybackRate(settings.playbackSpeed)

        // Restore assignment if present
        if let assignment = assignmentProvider?(display.id),
           let (wallpaper, url) = wallpaperResolver?(assignment.wallpaperID) {
            session.loadWallpaper(wallpaper, resolvedURL: url, scalingMode: assignment.scalingMode)
        }

        AppLogger.wallpaper.info("Created wallpaper session for display: \(display.name) (\(display.id))")
    }

    public func assignWallpaper(_ wallpaper: Wallpaper, resolvedURL: URL, toDisplayID displayID: String, scalingMode: ScalingMode) {
        if let session = activeSessions[displayID] {
            session.loadWallpaper(wallpaper, resolvedURL: resolvedURL, scalingMode: scalingMode)
        } else if let display = displayManager.displays.first(where: { $0.id == displayID }) {
            createSession(for: display)
            activeSessions[displayID]?.loadWallpaper(wallpaper, resolvedURL: resolvedURL, scalingMode: scalingMode)
        }
        reevaluatePolicy()
    }

    public func assignWallpaperToAllDisplays(_ wallpaper: Wallpaper, resolvedURL: URL, scalingMode: ScalingMode) {
        for display in displayManager.displays {
            assignWallpaper(wallpaper, resolvedURL: resolvedURL, toDisplayID: display.id, scalingMode: scalingMode)
        }
    }

    public func updateScalingMode(_ mode: ScalingMode, forDisplayID displayID: String) {
        activeSessions[displayID]?.setScalingMode(mode)
    }

    public func updatePlaybackSettings(_ settings: LiveWallpaperSettings) {
        for (_, session) in activeSessions {
            session.setMuted(settings.muteByDefault)
            session.setVolume(settings.volume)
            session.setPlaybackRate(settings.playbackSpeed)
        }
        reevaluatePolicy()
    }

    // MARK: - DisplayManagerDelegate
    public func displayManager(_ manager: DisplayManager, didDetectAdded displays: [DisplayDescriptor]) {
        for d in displays {
            createSession(for: d)
        }
    }

    public func displayManager(_ manager: DisplayManager, didDetectRemoved displayIDs: [String]) {
        for id in displayIDs {
            activeSessions[id]?.destroy()
            activeSessions.removeValue(forKey: id)
        }
    }

    public func displayManager(_ manager: DisplayManager, didDetectGeometryChange display: DisplayDescriptor) {
        if let screen = displayManager.screen(for: display.id) {
            activeSessions[display.id]?.updateGeometry(screen: screen, descriptor: display)
        }
    }

    public func displayManagerDidReconcile(_ manager: DisplayManager) {
        reconcile()
    }

    // MARK: - WallpaperSessionDelegate
    public func wallpaperSession(_ session: WallpaperSession, stateDidChange state: WallpaperPlaybackState) {
        AppLogger.wallpaper.info("Display [\(session.display.name)] state: \(state.label)")
        objectWillChange.send()
    }

    public func tearDownAll() {
        for (_, session) in activeSessions {
            session.destroy()
        }
        activeSessions.removeAll()
    }
}
