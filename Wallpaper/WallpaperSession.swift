import Foundation
import AppKit
import AVFoundation

@MainActor
public protocol WallpaperSessionDelegate: AnyObject {
    func wallpaperSession(_ session: WallpaperSession, stateDidChange state: WallpaperPlaybackState)
}

/// Represents an isolated video playback and window session on a single display.
/// Adheres to Section 9 of the specification.
@MainActor
public final class WallpaperSession: NSObject, VideoPlayerDelegate {
    public let displayID: String
    public private(set) var display: DisplayDescriptor
    public private(set) var currentWallpaper: Wallpaper?
    public private(set) var playbackState: WallpaperPlaybackState = .stopped
    public private(set) var scalingMode: ScalingMode = .fill

    public weak var delegate: WallpaperSessionDelegate?

    private var window: WallpaperWindow?
    private var contentView: WallpaperContentView?
    private let player: VideoPlayer
    private var policyAction: WallpaperPolicy.PolicyAction = .play

    public init(screen: NSScreen, display: DisplayDescriptor) {
        self.displayID = display.id
        self.display = display
        self.player = VideoPlayer()

        super.init()

        self.player.delegate = self
        setupWindow(screen: screen)
    }

    private func setupWindow(screen: NSScreen) {
        let win = WallpaperWindow(screen: screen, displayID: displayID)
        let view = WallpaperContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.attach(player: player.avPlayer)

        win.contentView = view
        self.window = win
        self.contentView = view

        win.orderFrontRegardless()
    }

    public func setScalingMode(_ mode: ScalingMode) {
        self.scalingMode = mode
        contentView?.updateScalingMode(mode)
    }

    public func updateGeometry(screen: NSScreen, descriptor: DisplayDescriptor) {
        self.display = descriptor
        window?.updateGeometry(for: screen)
        contentView?.setNeedsDisplay(contentView?.bounds ?? .zero)
        window?.orderFrontRegardless()
    }

    public func loadWallpaper(_ wallpaper: Wallpaper, resolvedURL: URL, scalingMode: ScalingMode) {
        self.currentWallpaper = wallpaper
        self.scalingMode = scalingMode
        contentView?.updateScalingMode(scalingMode)

        window?.orderFrontRegardless()
        setState(.loading)
        player.load(url: resolvedURL)
    }

    public func applyPolicy(action: WallpaperPolicy.PolicyAction) {
        self.policyAction = action
        switch action {
        case .play:
            if currentWallpaper != nil {
                window?.orderFrontRegardless()
                player.play()
                setState(.playing)
            }
        case .pause(let reason):
            player.pause()
            setState(.paused(reason: reason))
        case .stop:
            player.stop()
            setState(.stopped)
        }
    }

    public func stop() {
        player.stop()
        currentWallpaper = nil
        window?.orderOut(nil)
        setState(.stopped)
    }

    public func setMuted(_ muted: Bool) {
        player.setMuted(muted)
    }

    public func setVolume(_ volume: Float) {
        player.setVolume(volume)
    }

    public func setPlaybackRate(_ rate: Float) {
        player.setPlaybackRate(rate)
    }

    private func setState(_ newState: WallpaperPlaybackState) {
        guard playbackState != newState else { return }
        self.playbackState = newState
        delegate?.wallpaperSession(self, stateDidChange: newState)
    }

    // MARK: - VideoPlayerDelegate
    public func videoPlayerDidBecomeReady(_ player: VideoPlayer) {
        AppLogger.wallpaper.info("Player ready for display: \(self.display.name)")
        window?.orderFrontRegardless()
        if policyAction == .play {
            self.player.play()
            setState(.playing)
        } else if case .pause(let reason) = policyAction {
            setState(.paused(reason: reason))
        }
    }

    public func videoPlayerDidReachEnd(_ player: VideoPlayer) {
        // Seamless loop completed
    }

    public func videoPlayer(_ player: VideoPlayer, didFailWith error: WallpaperError) {
        AppLogger.wallpaper.error("Playback failed for display \(self.display.name): \(error.localizedDescription)")
        setState(.failed(error: error))
    }

    public func destroy() {
        player.cleanup()
        window?.orderOut(nil)
        window?.close()
        window = nil
        contentView = nil
        setState(.stopped)
    }
}
