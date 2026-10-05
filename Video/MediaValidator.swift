import Foundation
import AVFoundation

/// Validates media files and extracts technical metadata asynchronously.
/// Adheres to Section 12 and Section 29 of the specification.
public enum MediaValidator {
    public static func validate(url: URL) async throws -> VideoMetadata {
        // 1. Confirm file exists and is accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WallpaperError.fileMissing(path: url.path)
        }
        // Test readability directly using FileHandle rather than isReadableFile (which fails under sandbox)
        if (try? FileHandle(forReadingFrom: url)) == nil && !FileManager.default.isReadableFile(atPath: url.path) {
            throw WallpaperError.accessDenied(path: url.path)
        }

        // 2. Validate container format
        guard FileUtils.isSupportedVideoFormat(url: url) else {
            throw WallpaperError.unsupportedMedia(reason: "File extension .\(url.pathExtension) is not supported. Use MP4 or MOV.")
        }

        // 3. Inspect AVAsset
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])

        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                throw WallpaperError.corruptMedia(reason: "Asset is marked unplayable by AVFoundation.")
            }

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                throw WallpaperError.unsupportedMedia(reason: "The media file does not contain a playable video track.")
            }

            let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            let durationCM = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(durationCM)

            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

            // Account for display transform (rotation / orientation)
            let transformedSize = naturalSize.applying(transform)
            let width = Int(abs(transformedSize.width))
            let height = Int(abs(transformedSize.height))

            // Codec string
            var codec = "Unknown"
            if let descriptions = try? await videoTrack.load(.formatDescriptions),
               let firstDesc = descriptions.first {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(firstDesc)
                codec = fourCCToString(mediaSubType)
            }

            return VideoMetadata(
                duration: durationSeconds > 0 ? durationSeconds : 0,
                width: width > 0 ? width : 1920,
                height: height > 0 ? height : 1080,
                frameRate: nominalFrameRate > 0 ? Double(nominalFrameRate) : 30.0,
                hasVideoTrack: true,
                hasAudioTrack: !audioTracks.isEmpty,
                codec: codec
            )
        } catch let err as WallpaperError {
            throw err
        } catch {
            throw WallpaperError.corruptMedia(reason: error.localizedDescription)
        }
    }

    private static func fourCCToString(_ code: FourCharCode) -> String {
        let chars: [CChar] = [
            CChar((code >> 24) & 0xff),
            CChar((code >> 16) & 0xff),
            CChar((code >> 8) & 0xff),
            CChar(code & 0xff),
            0
        ]
        return String(cString: chars)
    }
}
