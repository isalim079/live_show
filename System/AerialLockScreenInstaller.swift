import Foundation
import AppKit
import AVFoundation
import CoreMedia
import Darwin

/// Installs Live Show videos into Apple's native Aerial wallpaper catalog for lock-screen playback
/// (WallpaperAerialsExtension) — the same pipeline Wallper uses on macOS 26/27.
/// Not MainActor-bound: encoding is CPU-heavy and runs off the UI thread.
public final class AerialLockScreenInstaller: @unchecked Sendable {
    public static let shared = AerialLockScreenInstaller()

    /// Stable category / subcategory IDs owned by Live Show (do not collide with Apple catalog).
    public static let categoryID = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
    public static let subcategoryID = "B2C3D4E5-F6A7-8901-BCDE-F12345678901"

    public private(set) var lastAssetID: String?
    public private(set) var lastErrorDetail: String = ""

    private var aerialsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")
    }

    private var videosDir: URL { aerialsRoot.appendingPathComponent("videos") }
    private var thumbnailsDir: URL { aerialsRoot.appendingPathComponent("thumbnails") }
    private var manifestDir: URL { aerialsRoot.appendingPathComponent("manifest") }
    private var entriesURL: URL { manifestDir.appendingPathComponent("entries.json") }
    private var indexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    /// True when this Mac can use the native Aerial lock-screen path (macOS 26+).
    public static var isSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        // Fallback: Darwin 25+ ≈ macOS 26 Tahoe; Darwin 26+ ≈ macOS 27
        var uts = utsname()
        uname(&uts)
        let release = withUnsafePointer(to: &uts.release) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
        let major = Int(release.split(separator: ".").first ?? "0") ?? 0
        return major >= 25
    }

    private init() {}

    /// Encode + register + set Desktop/Idle to the aerial asset. Safe to call from wallpaper set / Repair.
    /// `onProgress` receives human-readable status strings (may be called off the main actor).
    @discardableResult
    public func install(
        videoURL: URL,
        wallpaperID: UUID,
        title: String,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) -> Bool {
        guard Self.isSupported else {
            lastErrorDetail = "Native Aerial lock screen requires macOS 26+"
            AppLogger.wallpaper.warning("\(self.lastErrorDetail)")
            return false
        }

        do {
            try ensureDirectoryLayout()

            onProgress?("Encoding lock-screen video…")
            let encodedURL = try AerialTemporalEncoder.encodeIfNeeded(
                wallpaperID: wallpaperID,
                sourceURL: videoURL
            )

            onProgress?("Registering Aerial wallpaper…")
            let assetID = wallpaperID.uuidString.uppercased()
            let videoDest = videosDir.appendingPathComponent("\(assetID).mov")
            let thumbDest = thumbnailsDir.appendingPathComponent("\(assetID).png")

            if FileManager.default.fileExists(atPath: videoDest.path) {
                try FileManager.default.removeItem(at: videoDest)
            }
            try FileManager.default.copyItem(at: encodedURL, to: videoDest)
            stripXattrs(at: videoDest)

            try writeThumbnail(from: encodedURL, to: thumbDest)
            try patchEntriesJSON(assetID: assetID, title: title, videoURL: videoDest, thumbnailURL: thumbDest)
            try setWallpaperSlotsToAerial(assetID: assetID)
            refreshWallpaperAgents()

            lastAssetID = assetID
            lastErrorDetail = ""
            onProgress?("Lock screen ready")
            AppLogger.wallpaper.info("Installed Aerial Desktop+Idle asset \(assetID)")
            return true
        } catch {
            lastErrorDetail = error.localizedDescription
            onProgress?("Failed: \(error.localizedDescription)")
            AppLogger.wallpaper.error("Aerial lock-screen install failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Readiness

    public struct AerialReadiness: Equatable {
        public var supported: Bool
        public var assetPresent: Bool
        public var videoPresent: Bool
        public var idleProviderOK: Bool
        public var idleAssetOK: Bool
        public var desktopProviderOK: Bool
        public var desktopAssetOK: Bool
        public var detail: String
        public var assetID: String?

        public var isReady: Bool {
            supported && assetPresent && videoPresent
                && idleProviderOK && idleAssetOK
                && desktopProviderOK && desktopAssetOK
        }

        public var summary: String { isReady ? "Ready (Desktop+Idle Aerial)" : "Needs attention" }
    }

    public func inspectReadiness(expectedAssetID: String? = nil) -> AerialReadiness {
        guard Self.isSupported else {
            return AerialReadiness(
                supported: false, assetPresent: false, videoPresent: false,
                idleProviderOK: false, idleAssetOK: false,
                desktopProviderOK: false, desktopAssetOK: false,
                detail: "Requires macOS 26+", assetID: nil
            )
        }

        let assetID = expectedAssetID ?? lastAssetID ?? loadLiveShowAssetIDs().first
        guard let assetID else {
            return AerialReadiness(
                supported: true, assetPresent: false, videoPresent: false,
                idleProviderOK: false, idleAssetOK: false,
                desktopProviderOK: false, desktopAssetOK: false,
                detail: "No Live Show aerial asset registered", assetID: nil
            )
        }

        let videoOK = FileManager.default.fileExists(
            atPath: videosDir.appendingPathComponent("\(assetID).mov").path
        )
        let inCatalog = loadLiveShowAssetIDs().contains(assetID)
        let idle = inspectSlot(named: "Idle", expectedAssetID: assetID)
        let desktop = inspectSlot(named: "Desktop", expectedAssetID: assetID)

        var parts: [String] = []
        if !inCatalog { parts.append("missing from entries.json") }
        if !videoOK { parts.append("video file missing") }
        if !idle.providerOK { parts.append("Idle not aerials") }
        else if !idle.assetOK { parts.append("Idle assetID mismatch") }
        if !desktop.providerOK { parts.append("Desktop not aerials") }
        else if !desktop.assetOK { parts.append("Desktop assetID mismatch") }
        let detail = parts.isEmpty
            ? "Desktop+Idle → aerials \(assetID)"
            : parts.joined(separator: "; ")

        return AerialReadiness(
            supported: true,
            assetPresent: inCatalog,
            videoPresent: videoOK,
            idleProviderOK: idle.providerOK,
            idleAssetOK: idle.assetOK,
            desktopProviderOK: desktop.providerOK,
            desktopAssetOK: desktop.assetOK,
            detail: detail,
            assetID: assetID
        )
    }

    // MARK: - Catalog

    private func ensureDirectoryLayout() throws {
        let fm = FileManager.default
        for dir in [aerialsRoot, videosDir, thumbnailsDir, manifestDir] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
        if !fm.fileExists(atPath: entriesURL.path) {
            // Seed minimal catalog if WallpaperAgent hasn't created one yet
            let seed: [String: Any] = [
                "assets": [[String: Any]](),
                "categories": [[String: Any]](),
                "version": 1,
                "initialAssetCount": 0,
                "localizationVersion": "live-show"
            ]
            let data = try JSONSerialization.data(withJSONObject: seed, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: entriesURL, options: .atomic)
        }
    }

    private func patchEntriesJSON(assetID: String, title: String, videoURL: URL, thumbnailURL: URL) throws {
        let data = try Data(contentsOf: entriesURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "AerialLockScreen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid entries.json"])
        }

        var assets = root["assets"] as? [[String: Any]] ?? []
        var categories = root["categories"] as? [[String: Any]] ?? []

        // Ensure Live Show category
        let thumbFileURL = thumbnailURL.absoluteString
        let videoFileURL = videoURL.absoluteString
        if let idx = categories.firstIndex(where: { ($0["id"] as? String) == Self.categoryID }) {
            var cat = categories[idx]
            cat["localizedNameKey"] = "Live Show"
            cat["localizedDescriptionKey"] = "Live Show custom aerials"
            cat["previewImage"] = thumbFileURL
            cat["representativeAssetID"] = assetID
            var subs = cat["subcategories"] as? [[String: Any]] ?? []
            if let sidx = subs.firstIndex(where: { ($0["id"] as? String) == Self.subcategoryID }) {
                var sub = subs[sidx]
                sub["localizedNameKey"] = "Live Show"
                sub["localizedDescriptionKey"] = "Live Show"
                sub["previewImage"] = thumbFileURL
                sub["representativeAssetID"] = assetID
                subs[sidx] = sub
            } else {
                subs.append(makeSubcategory(preview: thumbFileURL, assetID: assetID))
            }
            cat["subcategories"] = subs
            categories[idx] = cat
        } else {
            categories.append([
                "id": Self.categoryID,
                "localizedNameKey": "Live Show",
                "localizedDescriptionKey": "Live Show custom aerials",
                "preferredOrder": 9000,
                "previewImage": thumbFileURL,
                "representativeAssetID": assetID,
                "subcategories": [makeSubcategory(preview: thumbFileURL, assetID: assetID)]
            ])
        }

        let assetEntry: [String: Any] = [
            "id": assetID,
            "accessibilityLabel": title,
            "localizedNameKey": title,
            "categories": [Self.categoryID],
            "subcategories": [Self.subcategoryID],
            "includeInShuffle": false,
            "pointsOfInterest": [String: Any](),
            "preferredOrder": 0,
            "previewImage": thumbFileURL,
            "shotID": "LIVESHOW_\(assetID.prefix(8))",
            "showInTopLevel": true,
            "url-4K-SDR-240FPS": videoFileURL
        ]

        if let aidx = assets.firstIndex(where: { ($0["id"] as? String)?.caseInsensitiveCompare(assetID) == .orderedSame }) {
            assets[aidx] = assetEntry
        } else {
            assets.append(assetEntry)
        }

        root["assets"] = assets
        root["categories"] = categories

        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: entriesURL, options: .atomic)
    }

    private func makeSubcategory(preview: String, assetID: String) -> [String: Any] {
        [
            "id": Self.subcategoryID,
            "localizedNameKey": "Live Show",
            "localizedDescriptionKey": "Live Show",
            "preferredOrder": 0,
            "previewImage": preview,
            "representativeAssetID": assetID,
            "combineVariants": false
        ]
    }

    private func loadLiveShowAssetIDs() -> [String] {
        guard let data = try? Data(contentsOf: entriesURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = root["assets"] as? [[String: Any]] else { return [] }
        return assets.compactMap { asset in
            guard let id = asset["id"] as? String,
                  let cats = asset["categories"] as? [String],
                  cats.contains(Self.categoryID) else { return nil }
            return id.uppercased()
        }
    }

    // MARK: - Thumbnail

    private func writeThumbnail(from videoURL: URL, to dest: URL) throws {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)

        let sem = DispatchSemaphore(value: 0)
        var cgImage: CGImage?
        var genError: Error?
        Task {
            do {
                let (img, _) = try await generator.image(at: time)
                cgImage = img
            } catch {
                genError = error
            }
            sem.signal()
        }
        sem.wait()
        if let genError { throw genError }
        guard let cgImage else {
            throw NSError(domain: "AerialLockScreen", code: 2, userInfo: [NSLocalizedDescriptionKey: "No thumbnail frame"])
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "AerialLockScreen", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try png.write(to: dest, options: .atomic)
    }

    // MARK: - Desktop + Idle Index.plist (required on Golden Gate for lock animation)

    private func setWallpaperSlotsToAerial(assetID: String) throws {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            throw NSError(domain: "AerialLockScreen", code: 3, userInfo: [NSLocalizedDescriptionKey: "WallpaperAgent Index.plist missing"])
        }

        let xmlURL = FileManager.default.temporaryDirectory.appendingPathComponent("liveshow_wallpaper_index.plist")
        try run("/usr/bin/plutil", ["-convert", "xml1", "-o", xmlURL.path, indexURL.path])

        let xmlData = try Data(contentsOf: xmlURL)
        guard var plist = try PropertyListSerialization.propertyList(from: xmlData, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] else {
            throw NSError(domain: "AerialLockScreen", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Index.plist"])
        }

        let configData = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID],
            format: .binary,
            options: 0
        )
        let choice: [String: Any] = [
            "Configuration": configData,
            "Files": [String](),
            "Provider": "com.apple.wallpaper.choice.aerials"
        ]
        let content: [String: Any] = [
            "Choices": [choice],
            "EncodedOptionValues": "$null",
            "Shuffle": "$null"
        ]
        let slotEntry: [String: Any] = [
            "Content": content,
            "LastSet": Date(),
            "LastUse": Date()
        ]

        var updated = 0

        func applySlots(to entry: inout [String: Any]) {
            entry["Desktop"] = slotEntry
            entry["Idle"] = slotEntry
            updated += 2
        }

        if var allSpaces = plist["AllSpacesAndDisplays"] as? [String: Any] {
            applySlots(to: &allSpaces)
            plist["AllSpacesAndDisplays"] = allSpaces
        }
        if var sysDefault = plist["SystemDefault"] as? [String: Any] {
            applySlots(to: &sysDefault)
            plist["SystemDefault"] = sysDefault
        }
        if var displays = plist["Displays"] as? [String: Any] {
            for (displayID, value) in displays {
                guard var entry = value as? [String: Any] else { continue }
                applySlots(to: &entry)
                displays[displayID] = entry
            }
            plist["Displays"] = displays
        }
        if var spaces = plist["Spaces"] as? [String: Any] {
            for (spaceID, value) in spaces {
                guard var spaceEntry = value as? [String: Any] else { continue }
                if var defaultEntry = spaceEntry["Default"] as? [String: Any] {
                    applySlots(to: &defaultEntry)
                    spaceEntry["Default"] = defaultEntry
                }
                if var spaceDisplays = spaceEntry["Displays"] as? [String: Any] {
                    for (displayID, dispValue) in spaceDisplays {
                        guard var displayEntry = dispValue as? [String: Any] else { continue }
                        applySlots(to: &displayEntry)
                        spaceDisplays[displayID] = displayEntry
                    }
                    spaceEntry["Displays"] = spaceDisplays
                }
                spaces[spaceID] = spaceEntry
            }
            plist["Spaces"] = spaces
        }

        guard updated > 0 else {
            throw NSError(domain: "AerialLockScreen", code: 5, userInfo: [NSLocalizedDescriptionKey: "No Desktop/Idle slots found to patch"])
        }

        let outXML = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try outXML.write(to: xmlURL, options: .atomic)

        _ = try? run("/usr/bin/killall", ["-STOP", "WallpaperAgent"])
        try run("/usr/bin/plutil", ["-convert", "binary1", "-o", indexURL.path, xmlURL.path])
        _ = try? run("/usr/bin/killall", ["-CONT", "WallpaperAgent"])
        _ = try? run("/usr/bin/killall", ["-HUP", "WallpaperAgent"])

        AppLogger.wallpaper.info("Patched \(updated) Desktop+Idle slot(s) → aerials \(assetID)")
    }

    private func inspectSlot(named slot: String, expectedAssetID: String) -> (providerOK: Bool, assetOK: Bool, detail: String) {
        guard let data = try? Data(contentsOf: indexURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return (false, false, "Index.plist unreadable")
        }

        var providers: [String] = []
        var assetIDs: [String] = []

        func collectFromContainer(_ container: [String: Any]?) {
            guard let container, let slotEntry = container[slot] as? [String: Any],
                  let slotContent = slotEntry["Content"] as? [String: Any],
                  let choices = slotContent["Choices"] as? [[String: Any]],
                  let first = choices.first else { return }
            if let p = first["Provider"] as? String { providers.append(p) }
            if let cfg = first["Configuration"] as? Data,
               let dict = try? PropertyListSerialization.propertyList(from: cfg, options: [], format: nil) as? [String: Any],
               let id = dict["assetID"] as? String {
                assetIDs.append(id.uppercased())
            }
        }

        collectFromContainer(plist["AllSpacesAndDisplays"] as? [String: Any])
        if let displays = plist["Displays"] as? [String: Any] {
            for (_, v) in displays { collectFromContainer(v as? [String: Any]) }
        }

        let providerOK = !providers.isEmpty && providers.allSatisfy { $0 == "com.apple.wallpaper.choice.aerials" }
        let expected = expectedAssetID.uppercased()
        let assetOK = !assetIDs.isEmpty && assetIDs.allSatisfy { $0 == expected }
        return (providerOK, assetOK, "\(slot) providers=\(Set(providers)) assets=\(Set(assetIDs))")
    }

    // MARK: - Agents

    private func refreshWallpaperAgents() {
        // Prefer gentle HUP; if needed, terminate Aerial extension so it respawns cleanly.
        _ = try? run("/usr/bin/killall", ["-HUP", "WallpaperAgent"])
        _ = try? run("/usr/bin/killall", ["WallpaperAerialsExtension"])
        _ = try? run("/usr/bin/killall", ["WallpaperLegacyExtension"])
    }

    // MARK: - Helpers

    private func stripXattrs(at url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-rc", url.path]
        try? p.run()
        p.waitUntilExit()
    }

    @discardableResult
    private func run(_ launchPath: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
