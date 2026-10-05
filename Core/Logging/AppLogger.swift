import Foundation
import os.log

/// Centralized unified logging system for LiveWallpaper.
/// Categorized according to subsystem architectural components.
public enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.livewallpaper.app"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let wallpaper = Logger(subsystem: subsystem, category: "wallpaper")
    public static let video = Logger(subsystem: subsystem, category: "video")
    public static let display = Logger(subsystem: subsystem, category: "display")
    public static let power = Logger(subsystem: subsystem, category: "power")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let login = Logger(subsystem: subsystem, category: "login")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")

    /// In-memory ring buffer of recent diagnostic events for the Diagnostics UI.
    public static let diagnosticBuffer = DiagnosticBuffer()
}

/// Thread-safe in-memory log buffer for user-facing diagnostics.
public final class DiagnosticBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [DiagnosticEntry] = []
    private let maxEntries = 200

    public struct DiagnosticEntry: Identifiable, Sendable {
        public let id = UUID()
        public let timestamp: Date
        public let category: String
        public let level: String
        public let message: String
    }

    public func log(category: String, level: String = "INFO", message: String) {
        lock.lock()
        defer { lock.unlock() }

        let entry = DiagnosticEntry(timestamp: Date(), category: category, level: level, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func getEntries() -> [DiagnosticEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
