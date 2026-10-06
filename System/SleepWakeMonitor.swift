import Foundation
import AppKit
import Combine

/// Monitors system sleep/wake and screen lock/unlock transitions.
/// Adheres to Section 15 of the specification.
public final class SleepWakeMonitor: ObservableObject {
    @Published public private(set) var isSystemAsleep: Bool = false
    @Published public private(set) var areScreensAsleep: Bool = false
    @Published public private(set) var isScreenLocked: Bool = false

    public var onStateChange: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupObservers()
    }

    private func setupObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter

        wsCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                AppLogger.power.info("System will sleep.")
                self?.isSystemAsleep = true
                self?.onStateChange?()
            }
            .store(in: &cancellables)

        wsCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                AppLogger.power.info("System did wake.")
                self?.isSystemAsleep = false
                self?.onStateChange?()
            }
            .store(in: &cancellables)

        wsCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                AppLogger.power.info("Screens did sleep.")
                self?.areScreensAsleep = true
                self?.onStateChange?()
            }
            .store(in: &cancellables)

        wsCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                AppLogger.power.info("Screens did wake.")
                self?.areScreensAsleep = false
                self?.onStateChange?()
            }
            .store(in: &cancellables)

        // Distributed notifications for Screen Lock and Screen Unlock
        let distCenter = DistributedNotificationCenter.default()

        distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.power.info("Screen is locked.")
            self?.isScreenLocked = true
            self?.onStateChange?()
            Task { @MainActor in
                ScreenSaverManager.shared.launchScreenSaverOnLock()
            }
        }

        distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.power.info("Screen is unlocked.")
            self?.isScreenLocked = false
            self?.onStateChange?()
        }
    }
}
