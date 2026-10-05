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

    public init() {
        refreshDisplays()
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                AppLogger.display.info("Display configuration change detected by system.")
                self?.reconcileDisplays()
            }
            .store(in: &cancellables)
    }

    /// Re-evaluates connected displays and dispatches reconciliation diffs.
    public func reconcileDisplays() {
        let previousDisplays = self.displays
        let currentScreens = NSScreen.screens

        var newDescriptors: [DisplayDescriptor] = []
        for (index, screen) in currentScreens.enumerated() {
            let descriptor = DisplayDescriptor.from(screen: screen, isPrimary: index == 0)
            newDescriptors.append(descriptor)
        }

        let previousIDs = Set(previousDisplays.map { $0.id })
        let currentIDs = Set(newDescriptors.map { $0.id })

        let addedIDs = currentIDs.subtracting(previousIDs)
        let removedIDs = previousIDs.subtracting(currentIDs)

        var added: [DisplayDescriptor] = []
        for d in newDescriptors where addedIDs.contains(d.id) {
            added.append(d)
        }

        self.displays = newDescriptors

        if !added.isEmpty {
            AppLogger.display.info("Detected \(added.count) new display(s): \(added.map { $0.name }.joined(separator: ", "))")
            delegate?.displayManager(self, didDetectAdded: added)
        }

        if !removedIDs.isEmpty {
            AppLogger.display.info("Detected \(removedIDs.count) removed display(s): \(Array(removedIDs).joined(separator: ", "))")
            delegate?.displayManager(self, didDetectRemoved: Array(removedIDs))
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
        self.displays = screens.enumerated().map { index, screen in
            DisplayDescriptor.from(screen: screen, isPrimary: index == 0)
        }
    }

    /// Finds the NSScreen matching a display ID.
    public func screen(for displayID: String) -> NSScreen? {
        for screen in NSScreen.screens {
            let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
            if let id = screen.deviceDescription[screenNumberKey] as? CGDirectDisplayID {
                if String(id) == displayID {
                    return screen
                }
            }
        }
        return nil
    }
}
