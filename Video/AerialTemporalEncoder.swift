import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Encodes lock-screen-compatible HEVC Main 10 with temporal scalability (`tscl`/`tsas`).
/// Required by WallpaperAerialsExtension on macOS 26/27 for unlock-ramp / lock playback.
public enum AerialTemporalEncoder {

    /// Cache generation — bump when encode policy changes so old short clips are not reused.
    private static let cacheGeneration = "v2loop"

    /// Target total duration so WallpaperAerialsExtension does not freeze after a short loop.
    private static let targetTotalSeconds: TimeInterval = 150
    /// Max seconds taken from the source per loop pass.
    private static let maxSegmentSeconds: TimeInterval = 30

    public enum EncoderError: Error, LocalizedError {
        case noVideoTrack
        case sessionCreateFailed(OSStatus)
        case writerFailed(String)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "Source has no video track"
            case .sessionCreateFailed(let s): return "VTCompressionSessionCreate failed (\(s))"
            case .writerFailed(let m): return m
            case .cancelled: return "Encoding cancelled"
            }
        }
    }

    /// Returns the cache path for a wallpaper source (mtime + generation stamped).
    public static func cachedOutputURL(for wallpaperID: UUID, sourceURL: URL) -> URL {
        let mtime = (try? sourceURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let stamp = String(format: "%.0f", mtime)
        return FileUtils.aerialCacheDirectory
            .appendingPathComponent("\(wallpaperID.uuidString)_\(stamp)_\(cacheGeneration).mov")
    }

    /// Returns a cached encode when fresh; otherwise encodes a looped ~2.5 minute clip.
    public static func encodeIfNeeded(
        wallpaperID: UUID,
        sourceURL: URL,
        bitrateMbps: Int = 10
    ) throws -> URL {
        let output = cachedOutputURL(for: wallpaperID, sourceURL: sourceURL)
        if FileManager.default.fileExists(atPath: output.path),
           FileUtils.fileSize(at: output) > 100_000 {
            return output
        }
        // Drop stale caches for this wallpaper id (including old v1 30s encodes)
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: FileUtils.aerialCacheDirectory,
            includingPropertiesForKeys: nil
        ) {
            for url in entries where url.lastPathComponent.hasPrefix(wallpaperID.uuidString) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        try encode(input: sourceURL, output: output, bitrateMbps: bitrateMbps)
        return output
    }

    public static func encode(
        input: URL,
        output: URL,
        bitrateMbps: Int = 10
    ) throws {
        try? FileManager.default.removeItem(at: output)

        let asset = AVURLAsset(url: input)
        let sem = DispatchSemaphore(value: 0)
        var loadError: Error?
        var videoTrack: AVAssetTrack?
        var naturalSize = CGSize.zero
        var nominalFPS: Float = 24
        var duration = CMTime.zero

        Task {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else { throw EncoderError.noVideoTrack }
                videoTrack = track
                naturalSize = try await track.load(.naturalSize)
                let t = try await track.load(.preferredTransform)
                let transformed = naturalSize.applying(t)
                naturalSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
                nominalFPS = try await track.load(.nominalFrameRate)
                duration = try await asset.load(.duration)
            } catch {
                loadError = error
            }
            sem.signal()
        }
        sem.wait()
        if let loadError { throw loadError }
        guard let vtrack = videoTrack else { throw EncoderError.noVideoTrack }

        let width = max(2, Int(naturalSize.width.rounded()))
        let height = max(2, Int(naturalSize.height.rounded()))
        if nominalFPS < 1 { nominalFPS = 24 }
        let bitrate = max(2, bitrateMbps) * 1_000_000

        let clipSeconds = max(CMTimeGetSeconds(duration), 0.1)
        let segmentSeconds = min(clipSeconds, maxSegmentSeconds)
        let loopCount = max(1, Int(ceil(targetTotalSeconds / segmentSeconds)))
        let segmentDuration = CMTime(seconds: segmentSeconds, preferredTimescale: 600)

        AppLogger.video.info(
            "Aerial encode \(width)x\(height) @\(nominalFPS)fps ×\(loopCount) loops (~\(Int(segmentSeconds * Double(loopCount)))s) → \(output.lastPathComponent)"
        )

        let writerBox = SampleBufferWriter(outputURL: output)
        let callback: VTCompressionOutputCallback = { refCon, _, status, _, sampleBuffer in
            guard status == noErr, let sampleBuffer else { return }
            let unm = Unmanaged<SampleBufferWriter>.fromOpaque(refCon!)
            unm.takeUnretainedValue().append(sampleBuffer)
        }

        var session: VTCompressionSession?
        let encoderSpec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
        ]
        let createStatus = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: encoderSpec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: callback,
            refcon: Unmanaged.passUnretained(writerBox).toOpaque(),
            compressionSessionOut: &session
        )
        guard createStatus == noErr, let session else {
            throw EncoderError.sessionCreateFailed(createStatus)
        }

        func setProp(_ key: CFString, _ value: CFTypeRef) {
            let s = VTSessionSetProperty(session, key: key, value: value)
            if s != noErr {
                AppLogger.video.warning("VT set \(key) failed: \(s)")
            }
        }

        setProp(kVTCompressionPropertyKey_RealTime, kCFBooleanFalse)
        setProp(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main10_AutoLevel)
        setProp(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanTrue)
        setProp(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: nominalFPS))
        setProp(kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: Int(nominalFPS * 5)))
        setProp(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: bitrate))
        setProp(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
        setProp(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
        setProp(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        setProp(kVTCompressionPropertyKey_AllowTemporalCompression, kCFBooleanTrue)
        setProp(kVTCompressionPropertyKey_BaseLayerFrameRate, NSNumber(value: Double(nominalFPS) / 2.0))
        VTCompressionSessionPrepareToEncodeFrames(session)

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        ]

        var fed = 0
        for loopIndex in 0..<loopCount {
            let offset = CMTimeMultiply(segmentDuration, multiplier: Int32(loopIndex))
            let reader = try AVAssetReader(asset: asset)
            let trackOutput = AVAssetReaderTrackOutput(track: vtrack, outputSettings: outputSettings)
            trackOutput.alwaysCopiesSampleData = false
            reader.add(trackOutput)
            reader.timeRange = CMTimeRange(start: .zero, duration: segmentDuration)
            guard reader.startReading() else {
                throw EncoderError.writerFailed(reader.error?.localizedDescription ?? "AVAssetReader failed")
            }

            while let sample = trackOutput.copyNextSampleBuffer() {
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                let pts = CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(sample), offset)
                var dur = CMSampleBufferGetDuration(sample)
                if !dur.isValid || dur.value == 0 {
                    dur = CMTime(value: 1, timescale: Int32(max(1, nominalFPS.rounded())))
                }
                VTCompressionSessionEncodeFrame(
                    session,
                    imageBuffer: imageBuffer,
                    presentationTimeStamp: pts,
                    duration: dur,
                    frameProperties: nil,
                    sourceFrameRefcon: nil,
                    infoFlagsOut: nil
                )
                fed += 1
            }
        }

        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        try writerBox.finish()
        AppLogger.video.info("Aerial encode complete: \(fed) frames → \(output.lastPathComponent)")
    }

    // MARK: - Writer

    private final class SampleBufferWriter: @unchecked Sendable {
        let outputURL: URL
        private var writer: AVAssetWriter?
        private var input: AVAssetWriterInput?
        private var started = false
        private var failedMessage: String?
        private let lock = NSLock()
        private var appended = 0

        init(outputURL: URL) {
            self.outputURL = outputURL
        }

        func append(_ sampleBuffer: CMSampleBuffer) {
            lock.lock()
            defer { lock.unlock() }
            if failedMessage != nil || !CMSampleBufferDataIsReady(sampleBuffer) { return }

            if !started {
                guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
                do {
                    let w = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
                    let inp = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
                    inp.expectsMediaDataInRealTime = false
                    w.add(inp)
                    w.startWriting()
                    w.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                    writer = w
                    input = inp
                    started = true
                } catch {
                    failedMessage = error.localizedDescription
                    return
                }
            }

            guard let input else { return }
            while !input.isReadyForMoreMediaData {
                usleep(500)
            }
            if !input.append(sampleBuffer) {
                failedMessage = writer?.error?.localizedDescription ?? "AVAssetWriterInput.append failed"
            } else {
                appended += 1
            }
        }

        func finish() throws {
            lock.lock()
            let w = writer
            let inp = input
            let fail = failedMessage
            let count = appended
            lock.unlock()

            if let fail { throw EncoderError.writerFailed(fail) }
            guard let w, let inp, count > 0 else {
                throw EncoderError.writerFailed("Nothing written to aerial encode")
            }
            inp.markAsFinished()
            let sem = DispatchSemaphore(value: 0)
            w.finishWriting { sem.signal() }
            sem.wait()
            guard w.status == .completed else {
                throw EncoderError.writerFailed(w.error?.localizedDescription ?? "Writer status \(w.status.rawValue)")
            }
        }
    }
}
