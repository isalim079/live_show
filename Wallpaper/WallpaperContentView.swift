import Foundation
import AppKit
import AVFoundation

/// Layer-backed native view hosting AVPlayerLayer at the desktop level.
/// Uses makeBackingLayer() so the view's backing layer is directly the AVPlayerLayer.
public final class WallpaperContentView: NSView {
    public var playerLayer: AVPlayerLayer {
        return self.layer as! AVPlayerLayer
    }

    public override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        autoresizingMask = [.width, .height]
        layer?.backgroundColor = NSColor.black.cgColor
    }

    public override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    public func attach(player: AVPlayer) {
        playerLayer.player = player
    }

    public func updateScalingMode(_ mode: ScalingMode) {
        switch mode {
        case .fill:
            playerLayer.videoGravity = .resizeAspectFill
        case .fit:
            playerLayer.videoGravity = .resizeAspect
        case .stretch:
            playerLayer.videoGravity = .resize
        }
    }
}
