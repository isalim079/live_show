import Foundation
import ScreenSaver
import AVFoundation
import AppKit

/// Native macOS Screen Saver plugin for LiveWallpaper.
/// Enables video playback on the macOS Screen Saver and Lock Screen.
@objc(LiveWallpaperSaverView)
public class LiveWallpaperSaverView: ScreenSaverView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setupPlayback()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlayback()
    }

    deinit {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        player?.pause()
    }

    private func setupPlayback() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        guard let videoURL = resolveActiveWallpaperURL() else {
            return
        }

        let avPlayer = AVPlayer(url: videoURL)
        avPlayer.actionAtItemEnd = .none
        avPlayer.isMuted = true
        self.player = avPlayer

        let layer = AVPlayerLayer(player: avPlayer)
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.layer?.addSublayer(layer)
        self.playerLayer = layer

        // Loop notification
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: avPlayer.currentItem,
            queue: .main
        ) { [weak avPlayer] _ in
            avPlayer?.seek(to: .zero)
            avPlayer?.play()
        }

        avPlayer.play()
    }

    private func resolveActiveWallpaperURL() -> URL? {
        let fileManager = FileManager.default

        // 1. Look in application support wallpapers
        let home = fileManager.homeDirectoryForCurrentUser
        let appSupportDirs = [
            home.appendingPathComponent("Library/Application Support/com.livewallpaper.app"),
            home.appendingPathComponent("Library/Containers/com.livewallpaper.app/Data/Library/Application Support/com.livewallpaper.app")
        ]

        for appSupport in appSupportDirs {
            let wallpapersDir = appSupport.appendingPathComponent("Wallpapers")
            if let files = try? fileManager.contentsOfDirectory(at: wallpapersDir, includingPropertiesForKeys: [.contentModificationDateKey]),
               let mostRecent = files.filter({ ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) })
                .sorted(by: {
                    let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    return d1 > d2
                }).first {
                return mostRecent
            }

            // Fallback: parse library.json
            let libURL = appSupport.appendingPathComponent("library.json")
            if let data = try? Data(contentsOf: libURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let wallpapers = json["wallpapers"] as? [[String: Any]],
               let first = wallpapers.first,
               let fileURLStr = first["fileURL"] as? String,
               let url = URL(string: fileURLStr),
               fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    public override func startAnimation() {
        super.startAnimation()
        player?.play()
    }

    public override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
    }

    public override func animateOneFrame() {
        // Handled by AVPlayerLayer
    }

    public override var hasConfigureSheet: Bool {
        return false
    }
}
