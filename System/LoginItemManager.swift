import Foundation
import ServiceManagement

/// Manages launch-at-login integration via SMAppService (macOS 13+).
/// Adheres to Section 16 of the specification.
public final class LoginItemManager: ObservableObject {
    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var requiresApproval: Bool = false

    public init() {
        checkStatus()
    }

    public func checkStatus() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            DispatchQueue.main.async {
                self.isEnabled = (status == .enabled)
                self.requiresApproval = (status == .requiresApproval)
            }
        }
    }

    public func setEnabled(_ enable: Bool) throws {
        if #available(macOS 13.0, *) {
            if enable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    AppLogger.login.info("Registered mainApp login item.")
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    AppLogger.login.info("Unregistered mainApp login item.")
                }
            }
            checkStatus()
        }
    }

    public func openSystemSettingsLoginItems() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
