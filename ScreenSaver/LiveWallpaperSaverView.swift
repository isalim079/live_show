import Foundation
import ScreenSaver
import AVFoundation
import AppKit

/// Native macOS Screen Saver plugin for Live Show.
///
/// Design:
/// - Runs inside ScreenSaverEngine / legacyScreenSaver at lock screen time.
/// - Reads ActiveWallpaper.mp4 from ~/Library/Screen Savers/ — a well-known,
///   sandbox-accessible path written by the main app whenever a wallpaper is set.
/// - Falls back to any .mp4 in ~/Library/Screen Savers/ if the well-known file
///   is missing, and finally to the bundled SampleAmbient.mp4.
/// - Uses AVPlayerLayer for hardware-accelerated, zero-copy video decoding.
/// - Loops seamlessly using AVPlayerLooper (requires AVQueuePlayer).
/// - Defers AV setup until bounds are non-zero (legacyScreenSaver may init with 0×0).
///
@objc(LiveWallpaperSaverView)
public class LiveWallpaperSaverView: ScreenSaverView {

    private var queuePlayer: AVQueuePlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?
    private var didSetupPlayback = false
    private var wantsPlayback = false

    // MARK: - Initializers

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        playerLooper?.disableLooping()
        queuePlayer?.pause()
        playerLayer?.removeFromSuperlayer()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        // Try immediately; if bounds are still zero, layout() will retry.
        trySetupPlaybackIfNeeded()
    }

    // MARK: - Layout

    public override func layout() {
        super.layout()
        trySetupPlaybackIfNeeded()
        syncPlayerLayerFrame()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        trySetupPlaybackIfNeeded()
        syncPlayerLayerFrame()
        if wantsPlayback {
            queuePlayer?.play()
        }
    }

    private func syncPlayerLayerFrame() {
        guard let playerLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    // MARK: - Setup

    private func trySetupPlaybackIfNeeded() {
        guard !didSetupPlayback else { return }
        // legacyScreenSaver on modern macOS can construct the view with a zero frame;
        // wait until we have a real size so AVPlayerLayer is not stuck at 0×0.
        guard bounds.width > 1, bounds.height > 1 else { return }
        setupPlayback()
    }

    private func setupPlayback() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        guard let videoURL = resolveActiveWallpaperURL() else {
            // Nothing to play — show black to avoid showing a stale desktop.
            didSetupPlayback = true
            return
        }

        let item = AVPlayerItem(url: videoURL)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none

        // AVPlayerLooper gives seamless frame-perfect looping
        let looper = AVPlayerLooper(player: player, templateItem: item)
        self.playerLooper = looper
        self.queuePlayer = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.layer?.addSublayer(layer)
        self.playerLayer = layer

        didSetupPlayback = true

        // Only start if ScreenSaverEngine has already asked us to animate.
        if wantsPlayback {
            player.play()
        }
    }

    // MARK: - URL Resolution

    private func resolveActiveWallpaperURL() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        // 1. Well-known file written by main app whenever the wallpaper changes.
        //    ScreenSaverEngine can always read ~/Library/Screen Savers/.
        let screensaversDir = home.appendingPathComponent("Library/Screen Savers")
        let wellKnownURL = screensaversDir.appendingPathComponent("ActiveWallpaper.mp4")
        if fileManager.fileExists(atPath: wellKnownURL.path) {
            return wellKnownURL
        }

        // 2. Any video in ~/Library/Screen Savers/ (most recently modified wins)
        if let entries = try? fileManager.contentsOfDirectory(
            at: screensaversDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) {
            let videos = entries
                .filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }
                .sorted {
                    let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    return d1 > d2
                }
            if let first = videos.first { return first }
        }

        // 3. Bundled sample video shipped inside the .saver bundle itself
        if let bundleURL = Bundle(for: type(of: self)).url(forResource: "SampleAmbient", withExtension: "mp4") {
            return bundleURL
        }

        return nil
    }

    // MARK: - ScreenSaverView lifecycle

    public override func startAnimation() {
        super.startAnimation()
        wantsPlayback = true
        trySetupPlaybackIfNeeded()
        syncPlayerLayerFrame()
        queuePlayer?.play()
    }

    public override func stopAnimation() {
        super.stopAnimation()
        wantsPlayback = false
        queuePlayer?.pause()
    }

    public override func animateOneFrame() {
        // Rendering handled entirely by AVPlayerLayer/Core Animation — no custom drawing needed.
        // Keep the layer sized in case the host resizes without calling layout().
        syncPlayerLayerFrame()
    }

    public override var hasConfigureSheet: Bool { false }
    public override var configureSheet: NSWindow? { nil }
}
