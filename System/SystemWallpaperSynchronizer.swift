import Foundation
import AppKit
import AVFoundation

/// Synchronizes macOS native desktop and Lock Screen wallpaper with the active live wallpaper.
/// Sets a full-resolution matching static frame as the system desktop image so that on reboot,
/// shutdown, cold boot, and Lock Screen, the wallpaper is always present with zero flicker.
@MainActor
public final class SystemWallpaperSynchronizer {
    public static let shared = SystemWallpaperSynchronizer()

    private init() {}

    /// Extracts and caches a full-resolution static frame from the video.
    public func getOrGenerateFrame(for videoURL: URL, id: UUID) async -> URL? {
        let destinationURL = FileUtils.systemFramesDirectory.appendingPathComponent("\(id.uuidString).jpg")

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Keep maximumSize at zero for full native resolution (e.g. 4K, 1080p)
        generator.maximumSize = .zero

        let targetTime = CMTime(seconds: 0.5, preferredTimescale: 600)

        do {
            let (cgImage, _) = try await generator.image(at: targetTime)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
                return nil
            }

            try jpegData.write(to: destinationURL, options: .atomic)
            AppLogger.wallpaper.info("Generated full-resolution system frame for \(videoURL.lastPathComponent)")
            return destinationURL
        } catch {
            AppLogger.wallpaper.warning("Could not generate high-res frame: \(error.localizedDescription)")
            // Fallback to thumbnail if high-res generation fails
            let thumbPath = FileUtils.thumbnailsDirectory.appendingPathComponent("\(id.uuidString).jpg")
            if FileManager.default.fileExists(atPath: thumbPath.path) {
                return thumbPath
            }
            return nil
        }
    }

    /// Synchronizes the macOS system desktop image for a specific screen.
    /// On macOS 26/27 with Aerial lock integration, skip applying JPEG Desktop so it does not
    /// overwrite the native aerial wallpaper required for Golden Gate lock-screen animation.
    public func sync(wallpaper: Wallpaper, videoURL: URL, for screen: NSScreen) {
        Task { @MainActor in
            // Always refresh the cached frame for cold-boot fallback, but do not apply as Desktop
            // when Aerial owns Desktop+Idle.
            let frameURL = await getOrGenerateFrame(for: videoURL, id: wallpaper.id)
            if AerialLockScreenInstaller.isSupported {
                AppLogger.wallpaper.info("Skipped JPEG Desktop sync (Aerial pipeline active) for '\(screen.localizedName)'")
                return
            }
            guard let frameURL else {
                AppLogger.wallpaper.warning("Cannot sync system wallpaper: failed to get frame")
                return
            }

            do {
                try NSWorkspace.shared.setDesktopImageURL(frameURL, for: screen, options: [:])
                AppLogger.wallpaper.info("Synced native macOS wallpaper for screen '\(screen.localizedName)'")
            } catch {
                AppLogger.wallpaper.error("Failed to set desktop image for screen: \(error.localizedDescription)")
            }
        }
    }

    /// Synchronizes all connected screens with the current wallpaper.
    public func syncAllScreens(wallpaper: Wallpaper, videoURL: URL) {
        Task { @MainActor in
            let frameURL = await getOrGenerateFrame(for: videoURL, id: wallpaper.id)
            if AerialLockScreenInstaller.isSupported {
                AppLogger.wallpaper.info("Skipped JPEG Desktop sync on all screens (Aerial pipeline active)")
                return
            }
            guard let frameURL else { return }

            for screen in NSScreen.screens {
                do {
                    try NSWorkspace.shared.setDesktopImageURL(frameURL, for: screen, options: [:])
                    AppLogger.wallpaper.info("Synced native macOS desktop/lock screen for '\(screen.localizedName)'")
                } catch {
                    AppLogger.wallpaper.error("Error setting system wallpaper on '\(screen.localizedName)': \(error.localizedDescription)")
                }
            }
        }
    }
}
