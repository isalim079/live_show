import Foundation
import AVFoundation
import CoreGraphics
import CoreMedia

/// Generates a smooth, seamless 1080p 60fps ambient animated video loop for testing LiveWallpaper.
func generateAmbientLoop(outputPath: String, durationSeconds: Double = 6.0, fps: Int32 = 60) async throws {
    let width = 1920
    let height = 1080
    let url = URL(fileURLWithPath: outputPath)

    if FileManager.default.fileExists(atPath: outputPath) {
        try? FileManager.default.removeItem(at: url)
    }

    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 6_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
        ]
    ]

    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    writerInput.expectsMediaDataInRealTime = false

    let sourcePixelBufferAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: writerInput,
        sourcePixelBufferAttributes: sourcePixelBufferAttributes
    )

    writer.add(writerInput)
    guard writer.startWriting() else {
        throw writer.error ?? NSError(domain: "AVAssetWriter", code: -1)
    }

    writer.startSession(atSourceTime: .zero)

    let totalFrames = Int(durationSeconds * Double(fps))
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    for frame in 0..<totalFrames {
        while !writerInput.isReadyForMoreMediaData {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool!, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { continue }

        CVPixelBufferLockBaseAddress(buffer, [])
        let data = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        if let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) {
            let progress = Double(frame) / Double(totalFrames)
            let angle = progress * 2.0 * .pi

            // Rich ambient dynamic gradient background
            let r1 = CGFloat(0.08 + 0.05 * sin(angle))
            let g1 = CGFloat(0.05 + 0.08 * cos(angle))
            let b1 = CGFloat(0.18 + 0.08 * sin(angle + .pi / 3))

            let r2 = CGFloat(0.35 + 0.15 * cos(angle))
            let g2 = CGFloat(0.12 + 0.10 * sin(angle * 2))
            let b2 = CGFloat(0.45 + 0.15 * cos(angle + .pi))

            let colors = [
                CGColor(red: r1, green: g1, blue: b1, alpha: 1.0),
                CGColor(red: r2, green: g2, blue: b2, alpha: 1.0)
            ] as CFArray

            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: CGFloat(width), y: CGFloat(height)),
                    options: []
                )
            }

            // Draw glowing ambient orb
            let centerX = CGFloat(width) / 2.0 + CGFloat(cos(angle) * 220.0)
            let centerY = CGFloat(height) / 2.0 + CGFloat(sin(angle) * 120.0)
            let orbColors = [
                CGColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0.7),
                CGColor(red: 0.2, green: 0.1, blue: 0.5, alpha: 0.0)
            ] as CFArray

            if let orbGradient = CGGradient(colorsSpace: colorSpace, colors: orbColors, locations: [0.0, 1.0]) {
                context.drawRadialGradient(
                    orbGradient,
                    startCenter: CGPoint(x: centerX, y: centerY),
                    startRadius: 0,
                    endCenter: CGPoint(x: centerX, y: centerY),
                    endRadius: 400,
                    options: []
                )
            }
        }

        CVPixelBufferUnlockBaseAddress(buffer, [])

        let presentationTime = CMTime(value: CMTimeValue(frame), timescale: fps)
        adaptor.append(buffer, withPresentationTime: presentationTime)
    }

    writerInput.markAsFinished()
    await withCheckedContinuation { continuation in
        writer.finishWriting {
            continuation.resume()
        }
    }
}

// Execute generator
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/SampleAmbient.mp4"
print("Generating ambient 1080p sample video to \(output)...")
Task {
    do {
        try await generateAmbientLoop(outputPath: output, durationSeconds: 4.0, fps: 30)
        print("Successfully generated sample ambient video.")
        exit(0)
    } catch {
        print("Generation failed: \(error)")
        exit(1)
    }
}
RunLoop.main.run()
