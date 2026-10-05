import Foundation
import AVFoundation
import AppKit

/// Asynchronously generates and caches lightweight video thumbnail images.
/// Adheres to Section 14 and Section 27 of the specification.
public enum ThumbnailGenerator {
    public static func generateThumbnail(for url: URL, id: UUID) async -> String? {
        let destinationURL = FileUtils.thumbnailsDirectory.appendingPathComponent("\(id.uuidString).jpg")

        // Return cached thumbnail if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return destinationURL.path
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        let targetTime = CMTime(seconds: 1.0, preferredTimescale: 600)

        do {
            let (cgImage, _) = try await generator.image(at: targetTime)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
                return nil
            }

            try jpegData.write(to: destinationURL, options: .atomic)
            return destinationURL.path
        } catch {
            AppLogger.video.warning("Could not generate thumbnail for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
}
