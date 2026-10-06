import Foundation
import AppKit
import Combine

/// Protocol for listening to display topology mutations.
@MainActor
public protocol DisplayManagerDelegate: AnyObject {
    func displayManager(_ manager: DisplayManager, didDetectAdded displays: [DisplayDescriptor])
    func displayManager(_ manager: DisplayManager, didDetectRemoved displayIDs: [String])
    func displayManager(_ manager: DisplayManager, didDetectGeometryChange display: DisplayDescriptor)
    func displayManagerDidReconcile(_ manager: DisplayManager)
}

/// Central manager for display lifecycle, matching Section 8 of the specification.
@MainActor
public final class DisplayManager: ObservableObject {
    @Published public private(set) var displays: [DisplayDescriptor] = []
    public weak var delegate: DisplayManagerDelegate?

    private var cancellables = Set<AnyCancellable>()
    private var debounceWorkItem: DispatchWorkItem?
    /// IDs missing from the latest snapshot; destroyed only if still missing on the next reconcile.
    private var pendingRemovalIDs: Set<String> = []
    private let debounceInterval: TimeInterval = 0.4

    public init() {
        refreshDisplays()
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                AppLogger.display.info("Display configuration change detected by system.")
                self?.scheduleReconcileDisplays()
            }
            .store(in: &cancellables)
    }

    /// Coalesces rapid topology flaps (common on wake) before reconciling.
    public func scheduleReconcileDisplays() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reconcileDisplays()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    /// Re-evaluates connected displays and dispatches reconciliation diffs.
    public func reconcileDisplays() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        let previousDisplays = self.displays
        let currentScreens = NSScreen.screens

        var newDescriptors: [DisplayDescriptor] = []
        var seenIDs = Set<String>()
        for (index, screen) in currentScreens.enumerated() {
            guard let descriptor = DisplayDescriptor.from(screen: screen, isPrimary: index == 0) else {
                continue
            }
            if seenIDs.contains(descriptor.id) {
                AppLogger.display.error("Duplicate display ID \(descriptor.id) for \(descriptor.name) — skipping")
                continue
            }
            seenIDs.insert(descriptor.id)
            newDescriptors.append(descriptor)
        }

        let previousIDs = Set(previousDisplays.map { $0.id })
        let currentIDs = Set(newDescriptors.map { $0.id })

        let addedIDs = currentIDs.subtracting(previousIDs)
        let missingIDs = previousIDs.subtracting(currentIDs)

        // Soft-remove: require two consecutive reconciles without a display before destroying.
        let confirmedRemoved = pendingRemovalIDs.intersection(missingIDs)
        pendingRemovalIDs = missingIDs.subtracting(confirmedRemoved)

        // Displays that reappeared clear pending removal.
        pendingRemovalIDs.subtract(currentIDs)

        var added: [DisplayDescriptor] = []
        for d in newDescriptors where addedIDs.contains(d.id) {
            added.append(d)
        }

        // Keep soft-pending displays in the published list so sessions are not torn down on wake flaps.
        var effectiveDisplays = newDescriptors
        for prev in previousDisplays where pendingRemovalIDs.contains(prev.id) {
            if !effectiveDisplays.contains(where: { $0.id == prev.id }) {
                effectiveDisplays.append(prev)
            }
        }
        self.displays = effectiveDisplays

        if !added.isEmpty {
            AppLogger.display.info("Detected \(added.count) new display(s): \(added.map { $0.name }.joined(separator: ", "))")
            delegate?.displayManager(self, didDetectAdded: added)
        }

        if !confirmedRemoved.isEmpty {
            AppLogger.display.info("Detected \(confirmedRemoved.count) removed display(s): \(Array(confirmedRemoved).joined(separator: ", "))")
            delegate?.displayManager(self, didDetectRemoved: Array(confirmedRemoved))
        } else if !pendingRemovalIDs.isEmpty {
            AppLogger.display.info("Deferring removal of transient display(s): \(Array(self.pendingRemovalIDs).joined(separator: ", "))")
        }

        // Check for geometry or scale mutations on existing displays
        for current in newDescriptors {
            if let previous = previousDisplays.first(where: { $0.id == current.id }) {
                if previous.frame != current.frame || previous.scaleFactor != current.scaleFactor {
                    AppLogger.display.info("Display geometry changed for: \(current.name)")
                    delegate?.displayManager(self, didDetectGeometryChange: current)
                }
            }
        }

        delegate?.displayManagerDidReconcile(self)
    }

    public func refreshDisplays() {
        let screens = NSScreen.screens
        var descriptors: [DisplayDescriptor] = []
        var seenIDs = Set<String>()
        for (index, screen) in screens.enumerated() {
            guard let descriptor = DisplayDescriptor.from(screen: screen, isPrimary: index == 0) else {
                continue
            }
            if seenIDs.contains(descriptor.id) { continue }
            seenIDs.insert(descriptor.id)
            descriptors.append(descriptor)
        }
        self.displays = descriptors
    }

    /// Finds the NSScreen matching a display ID.
    public func screen(for displayID: String) -> NSScreen? {
        for screen in NSScreen.screens {
            guard let id = DisplayDescriptor.cgDisplayID(from: screen) else { continue }
            if String(id) == displayID {
                return screen
            }
        }
        return nil
    }
}
