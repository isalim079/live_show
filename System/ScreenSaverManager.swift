import Foundation
import AppKit
import AVFoundation

/// Snapshot of whether the native Aerial lock-screen path is ready to animate.
public struct LockScreenReadiness: Equatable {
    public var usesAerialPipeline: Bool
    public var aerialAssetPresent: Bool
    public var aerialVideoPresent: Bool
    public var idleProviderOK: Bool
    public var idleAssetOK: Bool
    public var desktopProviderOK: Bool
    public var desktopAssetOK: Bool
    public var idleDetail: String
    public var aerialAssetID: String?
    /// Legacy .saver status (optional screensaver fallback; not used for lock Idle on macOS 26+).
    public var saverInstalled: Bool
    public var codesignOK: Bool
    public var codesignDetail: String

    public var isReady: Bool {
        if usesAerialPipeline {
            return aerialAssetPresent && aerialVideoPresent
                && idleProviderOK && idleAssetOK
                && desktopProviderOK && desktopAssetOK
        }
        return saverInstalled && codesignOK && idleProviderOK
    }

    public var summary: String {
        if isReady { return usesAerialPipeline ? "Ready (Desktop+Idle Aerial)" : "Ready" }
        return "Needs attention"
    }
}

public enum LockScreenJobPhase: String, Equatable {
    case idle
    case encoding
    case registering
    case done
    case failed

    public var isRunning: Bool {
        self == .encoding || self == .registering
    }
}

/// Manages installation and system settings integration for the macOS Screen Saver plugin.
@MainActor
public final class ScreenSaverManager: ObservableObject {
    public static let shared = ScreenSaverManager()

    @Published public private(set) var isInstalled: Bool = false
    @Published public private(set) var lastCodesignOK: Bool = false
    @Published public private(set) var lastCodesignDetail: String = "Not checked"
    @Published public private(set) var readiness: LockScreenReadiness?
    @Published public private(set) var lockScreenJobPhase: LockScreenJobPhase = .idle
    @Published public private(set) var lockScreenJobMessage: String = ""

    public func updateLockScreenJob(phase: LockScreenJobPhase, message: String) {
        lockScreenJobPhase = phase
        lockScreenJobMessage = message
    }

    public var destinationURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Screen Savers/LiveWallpaper.saver")
    }

    public var activeWallpaperURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers/ActiveWallpaper.mp4")
    }

    public init() {
        checkStatus()
    }

    public func checkStatus() {
        self.isInstalled = FileManager.default.fileExists(atPath: destinationURL.path)
    }

    /// Ensures optional .saver is present for Screen Saver prefs. Lock screen uses Aerial on macOS 26+.
    @discardableResult
    public func ensureInstalled() -> Bool {
        checkStatus()
        if isInstalled {
            let (ok, detail) = verifyCodesign(at: destinationURL)
            lastCodesignOK = ok
            lastCodesignDetail = detail
            if ok {
                // Register as system screensaver module only — do NOT overwrite Idle with .saver
                // when the native Aerial lock-screen pipeline is available.
                registerAsSystemScreenSaver(injectIntoIdle: !AerialLockScreenInstaller.isSupported)
                refreshReadiness()
                return true
            }
            AppLogger.wallpaper.warning("Installed .saver failed codesign verify (\(detail)); reinstalling.")
        }
        let success = installScreenSaver(injectIntoIdle: !AerialLockScreenInstaller.isSupported)
        refreshReadiness()
        return success
    }

    /// Installs or updates the Screen Saver bundle in ~/Library/Screen Savers/
    @discardableResult
    public func installScreenSaver(injectIntoIdle: Bool = false) -> Bool {
        let fileManager = FileManager.default
        let screensaversDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers")

        do {
            if !fileManager.fileExists(atPath: screensaversDir.path) {
                try fileManager.createDirectory(at: screensaversDir, withIntermediateDirectories: true)
            }

            // Look for bundled .saver in the app bundle
            guard let bundleSaverURL = Bundle.main.url(forResource: "LiveWallpaper", withExtension: "saver") else {
                AppLogger.wallpaper.warning("LiveWallpaper.saver not found in app bundle.")
                checkStatus()
                refreshReadiness()
                return false
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: bundleSaverURL, to: destinationURL)

            // CRITICAL: Strip quarantine and provenance extended attributes.
            stripExtendedAttributes(at: destinationURL)

            let (signed, signDetail) = resignScreenSaver(at: destinationURL)
            lastCodesignOK = signed
            lastCodesignDetail = signDetail
            if !signed {
                AppLogger.wallpaper.error("Failed to codesign installed .saver: \(signDetail)")
            }

            let (verified, verifyDetail) = verifyCodesign(at: destinationURL)
            lastCodesignOK = verified
            lastCodesignDetail = verifyDetail
            if verified {
                AppLogger.wallpaper.info("Installed and verified LiveWallpaper.saver at \(self.destinationURL.path)")
            } else {
                AppLogger.wallpaper.error("Installed LiveWallpaper.saver but codesign verify failed: \(verifyDetail)")
            }

            registerAsSystemScreenSaver(injectIntoIdle: injectIntoIdle)
            checkStatus()
            refreshReadiness()
            return verified

        } catch {
            AppLogger.wallpaper.error("Failed to install screen saver: \(error.localizedDescription)")
        }

        checkStatus()
        refreshReadiness()
        return false
    }

    /// Repairs lock-screen integration: native Aerial on macOS 26+, legacy .saver Idle otherwise.
    @discardableResult
    public func repairLockScreenIntegration() -> Bool {
        _ = installScreenSaver(injectIntoIdle: !AerialLockScreenInstaller.isSupported)
        refreshReadiness()
        return readiness?.isReady ?? false
    }

    /// Full lock-screen sync with visible progress (Settings / Diagnostics / set-wallpaper).
    @discardableResult
    public func performLockScreenSync(videoURL: URL, wallpaperID: UUID, title: String) async -> Bool {
        guard !lockScreenJobPhase.isRunning else {
            lockScreenJobMessage = "Lock screen update already in progress…"
            return false
        }

        lockScreenJobPhase = .encoding
        lockScreenJobMessage = "Encoding lock-screen video…"

        let useAerial = AerialLockScreenInstaller.isSupported
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard useAerial else { return true }
            return AerialLockScreenInstaller.shared.install(
                videoURL: videoURL,
                wallpaperID: wallpaperID,
                title: title,
                onProgress: { message in
                    Task { @MainActor in
                        let lower = message.lowercased()
                        let phase: LockScreenJobPhase
                        if lower.contains("fail") {
                            phase = .failed
                        } else if lower.contains("register") {
                            phase = .registering
                        } else if lower.contains("encoding") {
                            phase = .encoding
                        } else if lower.contains("ready") {
                            phase = .done
                        } else {
                            phase = .registering
                        }
                        ScreenSaverManager.shared.updateLockScreenJob(phase: phase, message: message)
                    }
                }
            )
        }.value

        updateActiveWallpaperLink(videoURL: videoURL, injectSaverIntoIdle: !useAerial)
        refreshReadiness()

        if useAerial {
            if ok {
                lockScreenJobPhase = .done
                lockScreenJobMessage = "Lock screen ready"
            } else {
                lockScreenJobPhase = .failed
                let detail = AerialLockScreenInstaller.shared.lastErrorDetail
                lockScreenJobMessage = detail.isEmpty ? "Failed to prepare lock screen" : "Failed: \(detail)"
            }
        } else {
            lockScreenJobPhase = ok ? .done : .failed
            lockScreenJobMessage = ok ? "Lock screen ready (Screen Saver)" : "Failed to prepare Screen Saver"
        }
        return ok
    }

    /// Syncs the active wallpaper to the lock-screen pipeline (Aerial on macOS 26+).
    @discardableResult
    public func syncLockScreen(videoURL: URL, wallpaperID: UUID, title: String) -> Bool {
        updateActiveWallpaperLink(videoURL: videoURL, injectSaverIntoIdle: !AerialLockScreenInstaller.isSupported)

        if AerialLockScreenInstaller.isSupported {
            let ok = AerialLockScreenInstaller.shared.install(
                videoURL: videoURL,
                wallpaperID: wallpaperID,
                title: title
            )
            refreshReadiness()
            return ok
        }
        refreshReadiness()
        return readiness?.isReady ?? false
    }

    /// Recursively strips extended attributes (quarantine, provenance, etc.) from a path.
    private func stripExtendedAttributes(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-rc", url.path]
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            AppLogger.wallpaper.info("Stripped xattrs from \(url.lastPathComponent)")
        }
    }

    /// Prefer Developer ID, then Apple Development, then ad-hoc.
    private func preferredSigningIdentity() -> String {
        if let env = ProcessInfo.processInfo.environment["CODE_SIGN_IDENTITY"], !env.isEmpty {
            return env
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-identity", "-p", "codesigning", "-v"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        for line in output.split(separator: "\n") {
            if line.contains("Developer ID Application:"),
               let start = line.range(of: "\""),
               let end = line.range(of: "\"", range: start.upperBound..<line.endIndex) {
                return String(line[start.upperBound..<end.lowerBound])
            }
        }
        for line in output.split(separator: "\n") {
            if line.contains("Apple Development:"),
               let start = line.range(of: "\""),
               let end = line.range(of: "\"", range: start.upperBound..<line.endIndex) {
                return String(line[start.upperBound..<end.lowerBound])
            }
        }
        return "-"
    }

    @discardableResult
    private func resignScreenSaver(at url: URL) -> (Bool, String) {
        let identity = preferredSigningIdentity()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = [
            "--force", "--deep", "--sign", identity,
            "--timestamp=none", url.path
        ]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, "codesign launch failed: \(error.localizedDescription)")
        }
        if process.terminationStatus == 0 {
            return (true, "Signed with \(identity == "-" ? "ad-hoc" : identity)")
        }
        let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "codesign failed"
        return (false, message)
    }

    private func verifyCodesign(at url: URL) -> (Bool, String) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (false, "Bundle missing")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", url.path]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, "verify launch failed: \(error.localizedDescription)")
        }
        let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Treat "valid on disk" / exit 0 as success. "internal error in Code Signing subsystem"
        // with non-zero exit is a failure that silently breaks lock-screen loading.
        if process.terminationStatus == 0 {
            return (true, message.isEmpty ? "Signature valid" : message)
        }
        return (false, message.isEmpty ? "codesign verify failed (status \(process.terminationStatus))" : message)
    }

    /// Opens macOS System Settings Screen Saver / Lock Screen preferences pane.
    public func openScreenSaverSettings() {
        let urlsToTry = [
            "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.desktopscreeneffect",
            "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
        ]
        for urlStr in urlsToTry {
            if let url = URL(string: urlStr), NSWorkspace.shared.open(url) {
                return
            }
        }
        if let settingsApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: settingsApp, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Registers LiveWallpaper as the active screen saver in macOS preferences.
    public func registerAsSystemScreenSaver(injectIntoIdle: Bool = false) {
        let path = destinationURL.path

        // Write via `defaults` so cfprefsd picks it up correctly for the current host
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = [
            "-currentHost", "write", "com.apple.screensaver", "moduleDict",
            "-dict", "path", path, "moduleName", "LiveWallpaper", "type", "0"
        ]
        try? process.run()
        process.waitUntilExit()

        // Flush cfprefsd so the preference is committed before ScreenSaverEngine reads it
        let killPrefsd = Process()
        killPrefsd.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killPrefsd.arguments = ["cfprefsd"]
        try? killPrefsd.run()
        killPrefsd.waitUntilExit()

        AppLogger.wallpaper.info("Registered LiveWallpaper.saver as active screen saver.")

        // Only inject .saver into Idle when native Aerial lock screen is unavailable.
        if injectIntoIdle {
            forceScreensaverIntoWallpaperAgent()
        }
    }

    /// On macOS Sequoia+, the lock screen is controlled by WallpaperAgent.
    /// Inject LiveWallpaper into every Idle slot so lock-screen animation works.
    private func forceScreensaverIntoWallpaperAgent() {
        let indexURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        let xmlURL = FileManager.default.temporaryDirectory.appendingPathComponent("wallpaper_index_edit.plist")

        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            AppLogger.wallpaper.warning("WallpaperAgent Index.plist not found, skipping lock screen injection")
            return
        }

        // 1. Convert binary plist to XML (so we can safely serialize/deserialize with $null)
        let convertToXML = Process()
        convertToXML.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        convertToXML.arguments = ["-convert", "xml1", "-o", xmlURL.path, indexURL.path]
        try? convertToXML.run()
        convertToXML.waitUntilExit()

        guard convertToXML.terminationStatus == 0,
              let xmlData = try? Data(contentsOf: xmlURL),
              var plist = try? PropertyListSerialization.propertyList(from: xmlData, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] else {
            AppLogger.wallpaper.error("Failed to read WallpaperAgent Index.plist as XML")
            return
        }

        // 2. Build the Configuration binary blob for the screen-saver provider
        let saverPath = destinationURL.path
        let configDict: [String: Any] = ["path": saverPath, "name": "LiveWallpaper"]
        guard let configData = try? PropertyListSerialization.data(fromPropertyList: configDict, format: .binary, options: 0) else {
            return
        }

        // 3. Build the Idle choice dictionary
        // Note: WallpaperAgent uses the string sentinel "$null" for empty optional fields.
        let idleChoice: [String: Any] = [
            "Configuration": configData,
            "Files": [String](),
            "Provider": "com.apple.wallpaper.choice.screen-saver"
        ]

        let idleContent: [String: Any] = [
            "Choices": [idleChoice],
            "EncodedOptionValues": "$null",
            "Shuffle": "$null"
        ]

        let idleEntry: [String: Any] = [
            "Content": idleContent,
            "LastSet": Date(),
            "LastUse": Date()
        ]

        var updated = 0

        // AllSpacesAndDisplays > Idle
        if var allSpaces = plist["AllSpacesAndDisplays"] as? [String: Any] {
            allSpaces["Idle"] = idleEntry
            plist["AllSpacesAndDisplays"] = allSpaces
            updated += 1
        }

        // SystemDefault > Idle
        if var sysDefault = plist["SystemDefault"] as? [String: Any] {
            sysDefault["Idle"] = idleEntry
            plist["SystemDefault"] = sysDefault
            updated += 1
        }

        // Displays[*].Idle
        if var displays = plist["Displays"] as? [String: Any] {
            for (displayID, value) in displays {
                guard var displayEntry = value as? [String: Any] else { continue }
                displayEntry["Idle"] = idleEntry
                displays[displayID] = displayEntry
                updated += 1
            }
            plist["Displays"] = displays
        }

        // Spaces[*].Default.Idle and Spaces[*].Displays[*].Idle
        if var spaces = plist["Spaces"] as? [String: Any] {
            for (spaceID, value) in spaces {
                guard var spaceEntry = value as? [String: Any] else { continue }

                if var defaultEntry = spaceEntry["Default"] as? [String: Any] {
                    defaultEntry["Idle"] = idleEntry
                    spaceEntry["Default"] = defaultEntry
                    updated += 1
                }

                if var spaceDisplays = spaceEntry["Displays"] as? [String: Any] {
                    for (displayID, dispValue) in spaceDisplays {
                        guard var displayEntry = dispValue as? [String: Any] else { continue }
                        displayEntry["Idle"] = idleEntry
                        spaceDisplays[displayID] = displayEntry
                        updated += 1
                    }
                    spaceEntry["Displays"] = spaceDisplays
                }

                spaces[spaceID] = spaceEntry
            }
            plist["Spaces"] = spaces
        }

        guard updated > 0 else {
            AppLogger.wallpaper.warning("Could not find Idle slots in Index.plist to patch")
            return
        }

        // 4. Write back to XML
        guard let outXMLData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            AppLogger.wallpaper.error("Failed to serialize modified Index.plist to XML")
            return
        }
        try? outXMLData.write(to: xmlURL, options: .atomic)

        // 5. Suspend WallpaperAgent to prevent race conditions while we write
        let suspendTask = Process()
        suspendTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        suspendTask.arguments = ["-STOP", "WallpaperAgent"]
        try? suspendTask.run()
        suspendTask.waitUntilExit()

        // 6. Convert patched XML back to Binary and overwrite Index.plist
        let convertToBinary = Process()
        convertToBinary.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        convertToBinary.arguments = ["-convert", "binary1", "-o", indexURL.path, xmlURL.path]
        try? convertToBinary.run()
        convertToBinary.waitUntilExit()

        // 7. Resume and HUP WallpaperAgent to apply changes
        let resumeTask = Process()
        resumeTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        resumeTask.arguments = ["-CONT", "WallpaperAgent"]
        try? resumeTask.run()
        resumeTask.waitUntilExit()

        let hupTask = Process()
        hupTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        hupTask.arguments = ["-HUP", "WallpaperAgent"]
        try? hupTask.run()
        hupTask.waitUntilExit()

        AppLogger.wallpaper.info("Successfully patched \(updated) WallpaperAgent Idle slot(s) for Lock Screen")
    }

    /// Copies the active wallpaper video into ~/Library/Screen Savers/ActiveWallpaper.mp4
    /// so the optional .saver can read it. Prefer `syncLockScreen` for full lock integration.
    public func updateActiveWallpaperLink(videoURL: URL, injectSaverIntoIdle: Bool = false) {
        let screensaversDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers")
        let linkURL = screensaversDir.appendingPathComponent("ActiveWallpaper.mp4")

        do {
            if !FileManager.default.fileExists(atPath: screensaversDir.path) {
                try FileManager.default.createDirectory(at: screensaversDir, withIntermediateDirectories: true)
            }

            if FileManager.default.fileExists(atPath: linkURL.path) {
                try FileManager.default.removeItem(at: linkURL)
            }

            try FileManager.default.copyItem(at: videoURL, to: linkURL)
            AppLogger.wallpaper.info("Copied video to Screen Savers dir: \(videoURL.lastPathComponent)")

            stripExtendedAttributes(at: linkURL)

            if injectSaverIntoIdle {
                forceScreensaverIntoWallpaperAgent()
            }
            refreshReadiness()

        } catch {
            AppLogger.wallpaper.error("Failed to update ActiveWallpaper.mp4: \(error.localizedDescription)")
            refreshReadiness()
        }
    }

    // MARK: - Readiness diagnostics

    public func refreshReadiness() {
        checkStatus()
        let (codesignOK, codesignDetail): (Bool, String) = {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                return verifyCodesign(at: destinationURL)
            }
            return (false, "Not installed")
        }()
        lastCodesignOK = codesignOK
        lastCodesignDetail = codesignDetail

        if AerialLockScreenInstaller.isSupported {
            let aerial = AerialLockScreenInstaller.shared.inspectReadiness()
            readiness = LockScreenReadiness(
                usesAerialPipeline: true,
                aerialAssetPresent: aerial.assetPresent,
                aerialVideoPresent: aerial.videoPresent,
                idleProviderOK: aerial.idleProviderOK,
                idleAssetOK: aerial.idleAssetOK,
                desktopProviderOK: aerial.desktopProviderOK,
                desktopAssetOK: aerial.desktopAssetOK,
                idleDetail: aerial.detail.isEmpty
                    ? (AerialLockScreenInstaller.shared.lastErrorDetail.isEmpty
                       ? "Checking…"
                       : AerialLockScreenInstaller.shared.lastErrorDetail)
                    : aerial.detail,
                aerialAssetID: aerial.assetID,
                saverInstalled: isInstalled,
                codesignOK: codesignOK,
                codesignDetail: codesignDetail
            )
        } else {
            let (idleProviderOK, idlePathOK, idleDetail) = inspectIdleSlots()
            readiness = LockScreenReadiness(
                usesAerialPipeline: false,
                aerialAssetPresent: false,
                aerialVideoPresent: false,
                idleProviderOK: idleProviderOK,
                idleAssetOK: idlePathOK,
                desktopProviderOK: false,
                desktopAssetOK: false,
                idleDetail: idleDetail,
                aerialAssetID: nil,
                saverInstalled: isInstalled,
                codesignOK: codesignOK,
                codesignDetail: codesignDetail
            )
        }
    }

    private func fileHasVideoTrack(_ url: URL) -> Bool {
        final class Box: @unchecked Sendable { var value = false }
        let box = Box()
        let group = DispatchGroup()
        group.enter()
        Task.detached {
            defer { group.leave() }
            let asset = AVURLAsset(url: url)
            if let tracks = try? await asset.loadTracks(withMediaType: .video) {
                box.value = !tracks.isEmpty
            }
        }
        _ = group.wait(timeout: .now() + 3)
        return box.value
    }

    private func inspectIdleSlots() -> (providerOK: Bool, pathOK: Bool, detail: String) {
        let indexURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return (false, false, "WallpaperAgent Index.plist missing")
        }

        var providers: [String] = []
        var paths: [String] = []

        func collect(from entry: [String: Any]?) {
            guard let content = entry?["Content"] as? [String: Any],
                  let choices = content["Choices"] as? [[String: Any]],
                  let first = choices.first else { return }
            if let provider = first["Provider"] as? String {
                providers.append(provider)
            }
            if let configData = first["Configuration"] as? Data,
               let config = try? PropertyListSerialization.propertyList(from: configData, options: [], format: nil) as? [String: Any],
               let path = config["path"] as? String {
                paths.append(path)
            }
        }

        if let all = plist["AllSpacesAndDisplays"] as? [String: Any] {
            collect(from: all["Idle"] as? [String: Any])
        }
        if let sys = plist["SystemDefault"] as? [String: Any] {
            collect(from: sys["Idle"] as? [String: Any])
        }
        if let displays = plist["Displays"] as? [String: Any] {
            for (_, value) in displays {
                collect(from: (value as? [String: Any])?["Idle"] as? [String: Any])
            }
        }

        let expectedPath = destinationURL.path
        let providerOK = !providers.isEmpty && providers.allSatisfy { $0 == "com.apple.wallpaper.choice.screen-saver" }
        let pathOK = !paths.isEmpty && paths.allSatisfy { $0 == expectedPath }

        if providers.isEmpty {
            return (false, false, "No Idle screen-saver entries found")
        }
        if !providerOK {
            return (false, pathOK, "Idle provider is not screen-saver")
        }
        if !pathOK {
            return (true, false, "Idle path does not point at LiveWallpaper.saver")
        }
        return (true, true, "Idle slots point at LiveWallpaper.saver (\(paths.count) checked)")
    }
}
