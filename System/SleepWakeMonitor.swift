import Foundation
import AppKit
import Combine
import CoreGraphics

/// Monitors system sleep/wake and screen lock/unlock transitions.
/// Adheres to Section 15 of the specification.
public final class SleepWakeMonitor: ObservableObject {
    public enum StateEvent {
        /// Flag-only change (e.g. willSleep, screensDidSleep, screen locked).
        case policy
        /// User returned: unlock, system wake, or screens wake — full session recovery needed.
        case wakeOrUnlock
    }

    @Published public private(set) var isSystemAsleep: Bool = false
    @Published public private(set) var areScreensAsleep: Bool = false
    @Published public private(set) var isScreenLocked: Bool = false

    public var onStateChange: ((StateEvent) -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?

    public init() {
        setupObservers()
        syncLockStateFromSession()
    }

    deinit {
        let distCenter = DistributedNotificationCenter.default()
        if let lockObserver {
            distCenter.removeObserver(lockObserver)
        }
        if let unlockObserver {
            distCenter.removeObserver(unlockObserver)
        }
    }

    /// Clears sticky sleep/lock flags after wake/unlock and re-samples real lock state.
    public func clearStickyFlagsAfterWake() {
        isSystemAsleep = false
        areScreensAsleep = false
        syncLockStateFromSession()
    }

    /// Samples the session dictionary for the current lock state (best-effort).
    public func syncLockStateFromSession() {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return }
        if let locked = dict["CGSSessionScreenIsLocked"] as? Bool {
            isScreenLocked = locked
        } else if let number = dict["CGSSessionScreenIsLocked"] as? NSNumber {
            isScreenLocked = number.boolValue
        }
    }

    private func setupObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter

        wsCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                AppLogger.power.info("System will sleep.")
                self?.isSystemAsleep = true
                self?.onStateChange?(.policy)
            }
            .store(in: &cancellables)

        wsCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                AppLogger.power.info("System did wake.")
                self?.isSystemAsleep = false
                self?.areScreensAsleep = false
                self?.syncLockStateFromSession()
                self?.onStateChange?(.wakeOrUnlock)
            }
            .store(in: &cancellables)

        wsCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                AppLogger.power.info("Screens did sleep.")
                self?.areScreensAsleep = true
                self?.onStateChange?(.policy)
            }
            .store(in: &cancellables)

        wsCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                AppLogger.power.info("Screens did wake.")
                self?.areScreensAsleep = false
                self?.syncLockStateFromSession()
                self?.onStateChange?(.wakeOrUnlock)
            }
            .store(in: &cancellables)

        // Distributed notifications for Screen Lock and Screen Unlock.
        // Tokens MUST be retained or delivery stops after the returned objects deallocate.
        let distCenter = DistributedNotificationCenter.default()

        lockObserver = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.power.info("Screen is locked.")
            self?.isScreenLocked = true
            self?.onStateChange?(.policy)
        }

        unlockObserver = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.power.info("Screen is unlocked.")
            self?.isScreenLocked = false
            // Lock often triggers screensDidSleep without a matching screensDidWake.
            self?.areScreensAsleep = false
            self?.syncLockStateFromSession()
            self?.onStateChange?(.wakeOrUnlock)
        }
    }
}
