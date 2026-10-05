import Foundation
import AVFoundation
import Combine

@MainActor
public protocol VideoPlayerDelegate: AnyObject {
    func videoPlayerDidBecomeReady(_ player: VideoPlayer)
    func videoPlayerDidReachEnd(_ player: VideoPlayer)
    func videoPlayer(_ player: VideoPlayer, didFailWith error: WallpaperError)
}

/// Native video player wrapper around AVPlayer and AVPlayerItem.
/// Adheres to Section 9 and Section 10 of the specification.
@MainActor
public final class VideoPlayer: NSObject, ObservableObject {
    public private(set) var avPlayer: AVPlayer
    public private(set) var currentItem: AVPlayerItem?
    public weak var delegate: VideoPlayerDelegate?

    @Published public private(set) var isReady: Bool = false
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var isMuted: Bool = true
    @Published public private(set) var volume: Float = 0.0
    @Published public private(set) var playbackRate: Float = 1.0

    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var errorObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?

    public init(player: AVPlayer = AVPlayer()) {
        self.avPlayer = player
        super.init()
        self.avPlayer.actionAtItemEnd = .none
        self.avPlayer.isMuted = true
        self.avPlayer.volume = 0.0
        self.avPlayer.preventsDisplaySleepDuringVideoPlayback = false
        self.avPlayer.automaticallyWaitsToMinimizeStalling = false

        setupTimeControlObserver()
    }

    deinit {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        statusObserver?.invalidate()
        errorObserver?.invalidate()
        timeControlObserver?.invalidate()
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
    }

    private func setupTimeControlObserver() {
        timeControlObserver = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.isPlaying = (player.timeControlStatus == .playing)
            }
        }
    }

    /// Loads an asset URL into the player pipeline.
    public func load(url: URL) {
        cleanupCurrentItem()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        self.currentItem = item

        // Status observation
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch playerItem.status {
                case .readyToPlay:
                    self.isReady = true
                    self.delegate?.videoPlayerDidBecomeReady(self)
                case .failed:
                    self.isReady = false
                    let desc = playerItem.error?.localizedDescription ?? "Unknown decoding failure"
                    AppLogger.video.error("AVPlayerItem failed: \(desc)")
                    self.delegate?.videoPlayer(self, didFailWith: .playbackFailed(reason: desc))
                default:
                    break
                }
            }
        }

        // Loop notification observer
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.loopPlayback()
                self.delegate?.videoPlayerDidReachEnd(self)
            }
        }

        avPlayer.replaceCurrentItem(with: item)
    }

    private func loopPlayback() {
        avPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isPlaying || self.isReady {
                    self.avPlayer.rate = self.playbackRate
                }
            }
        }
    }

    public func play() {
        guard isReady || currentItem?.status == .readyToPlay else {
            // Player will start upon ready
            avPlayer.rate = playbackRate
            return
        }
        avPlayer.rate = playbackRate
    }

    public func pause() {
        avPlayer.pause()
    }

    public func stop() {
        avPlayer.pause()
        avPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        avPlayer.isMuted = muted
    }

    public func setVolume(_ vol: Float) {
        let clamped = max(0.0, min(1.0, vol))
        self.volume = clamped
        avPlayer.volume = clamped
        if clamped > 0 {
            setMuted(false)
        }
    }

    public func setPlaybackRate(_ rate: Float) {
        self.playbackRate = rate
        if isPlaying {
            avPlayer.rate = rate
        }
    }

    private func cleanupCurrentItem() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        errorObserver?.invalidate()
        errorObserver = nil
        isReady = false
    }

    public func cleanup() {
        cleanupCurrentItem()
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
    }
}
