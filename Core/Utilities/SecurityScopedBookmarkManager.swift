import Foundation

/// Manages security-scoped bookmarks for sandboxed and non-sandboxed persistent file access.
/// Adheres to Section 13 of the specification.
public final class SecurityScopedBookmarkManager: @unchecked Sendable {
    public static let shared = SecurityScopedBookmarkManager()

    private let lock = NSLock()
    private var activeResources: Set<URL> = []

    private init() {}

    /// Creates bookmark data for a user-selected URL.
    public func createBookmark(for url: URL) throws -> Data {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        #if os(macOS)
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            // Fallback for non-sandboxed environments
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        #else
        return try url.bookmarkData()
        #endif
    }

    /// Resolves bookmark data to an accessible URL and begins accessing it.
    public func resolveBookmark(data: Data, staleHandler: ((Data) -> Void)? = nil) throws -> URL {
        var isStale = false
        #if os(macOS)
        let resolvedURL: URL
        do {
            resolvedURL = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            // Fallback for non-scoped bookmarks
            resolvedURL = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
        #else
        let resolvedURL = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
        #endif

        if isStale, let newBookmark = try? createBookmark(for: resolvedURL) {
            staleHandler?(newBookmark)
        }

        startAccessing(url: resolvedURL)
        return resolvedURL
    }

    /// Starts accessing a security-scoped URL, tracking reference.
    public func startAccessing(url: URL) {
        lock.lock()
        defer { lock.unlock() }

        if !activeResources.contains(url) {
            if url.startAccessingSecurityScopedResource() {
                activeResources.insert(url)
            }
        }
    }

    /// Stops accessing a security-scoped URL.
    public func stopAccessing(url: URL) {
        lock.lock()
        defer { lock.unlock() }

        if activeResources.contains(url) {
            url.stopAccessingSecurityScopedResource()
            activeResources.remove(url)
        }
    }

    /// Releases all tracked security-scoped resources.
    public func stopAccessingAll() {
        lock.lock()
        defer { lock.unlock() }

        for url in activeResources {
            url.stopAccessingSecurityScopedResource()
        }
        activeResources.removeAll()
    }
}
