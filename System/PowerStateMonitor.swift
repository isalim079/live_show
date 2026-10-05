import Foundation
import IOKit.ps

/// Monitors system power source (AC vs Battery) and charge level using IOKit.
/// Adheres to Section 15 of the specification.
public final class PowerStateMonitor: ObservableObject, @unchecked Sendable {
    @Published public private(set) var powerSource: PowerSourceState = .ac
    @Published public private(set) var batteryLevel: Int? = nil
    @Published public private(set) var isCharging: Bool = false

    private var runLoopSource: CFRunLoopSource?

    public init() {
        updatePowerState()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    public func updatePowerState() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            DispatchQueue.main.async {
                self.powerSource = .ac
                self.batteryLevel = nil
            }
            return
        }

        var detectedSource: PowerSourceState = .ac
        var level: Int? = nil
        var charging = false

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                if state == (kIOPSBatteryPowerValue as String) {
                    detectedSource = .battery
                } else {
                    detectedSource = .ac
                }
            }

            if let current = desc[kIOPSCurrentCapacityKey as String] as? Int,
               let max = desc[kIOPSMaxCapacityKey as String] as? Int, max > 0 {
                level = Int((Double(current) / Double(max)) * 100.0)
            }

            if let isCharge = desc[kIOPSIsChargingKey as String] as? Bool {
                charging = isCharge
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.powerSource = detectedSource
            self.batteryLevel = level
            self.isCharging = charging
        }
    }

    private func startMonitoring() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let loopSource = IOPSNotificationCreateRunLoopSource({ info in
            guard let info = info else { return }
            let monitor = Unmanaged<PowerStateMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.updatePowerState()
        }, context).takeRetainedValue()

        self.runLoopSource = loopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .defaultMode)
    }

    private func stopMonitoring() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            self.runLoopSource = nil
        }
    }
}
