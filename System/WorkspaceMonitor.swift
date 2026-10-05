import Foundation
import AppKit
import Combine

/// Monitors frontmost application changes and fullscreen state.
/// Adheres to Section 19 of the specification.
public final class WorkspaceMonitor: ObservableObject {
    @Published public private(set) var isFullscreenAppActive: Bool = false
    public var onFullscreenStateChanged: ((Bool) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupObservers()
    }

    private func setupObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter

        wsCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.evaluateFullscreenState()
            }
            .store(in: &cancellables)

        wsCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.evaluateFullscreenState()
            }
            .store(in: &cancellables)
    }

    public func evaluateFullscreenState() {
        // Safe, non-invasive check for frontmost application window
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        // Finder, Dock, or our own app are not fullscreen blockers
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier ||
           frontApp.bundleIdentifier == "com.apple.finder" ||
           frontApp.bundleIdentifier == "com.apple.dock" {
            setFullscreen(false)
            return
        }

        // On macOS, frontmost app in a separate Space usually has presentationOptions including fullScreen
        let isPresentationFullscreen = NSApp.currentSystemPresentationOptions.contains(.fullScreen)
        setFullscreen(isPresentationFullscreen)
    }

    private func setFullscreen(_ active: Bool) {
        if isFullscreenAppActive != active {
            isFullscreenAppActive = active
            onFullscreenStateChanged?(active)
        }
    }
}
