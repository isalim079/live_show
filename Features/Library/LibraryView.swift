import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Main wallpaper gallery and library management interface.
/// Adheres to Section 14, 18, and 22 of the specification.
public struct LibraryView: View {
    @ObservedObject var appState: AppState = AppState.shared
    @ObservedObject var store: WallpaperStore = AppState.shared.store

    @State private var searchText: String = ""
    @State private var isTargetedForDrop: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false
    @State private var isImporting: Bool = false

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 18)
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar Header
            HStack(spacing: 12) {
                Image(systemName: "photo.stack.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Wallpaper Library")
                    .font(.title2.bold())

                if !store.wallpapers.isEmpty {
                    Text("\(store.wallpapers.count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundColor(.accentColor)
                }

                Spacer()

                // Search Box
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search wallpapers...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 160)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

                // Import Button
                Button(action: {
                    selectAndImportFiles()
                }) {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Importing...")
                    } else {
                        Label("Import Video...", systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isImporting)
            }
            .padding()
            .background(.regularMaterial)

            Divider()

            // Content Area
            if filteredWallpapers.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(filteredWallpapers) { wallpaper in
                            WallpaperCard(
                                wallpaper: wallpaper,
                                appState: appState,
                                isActive: isWallpaperActive(wallpaper)
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 480)
        .onDrop(of: [UTType.movie.identifier, UTType.fileURL.identifier, UTType.video.identifier], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers: providers)
        }
        .alert("Import Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred while importing.")
        }
    }

    private var filteredWallpapers: [Wallpaper] {
        if searchText.isEmpty {
            return store.wallpapers
        }
        return store.wallpapers.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func isWallpaperActive(_ wallpaper: Wallpaper) -> Bool {
        return store.assignments.values.contains { $0.wallpaperID == wallpaper.id }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: isTargetedForDrop ? "arrow.down.doc.fill" : "sparkles.tv")
                .font(.system(size: 54))
                .foregroundColor(isTargetedForDrop ? .accentColor : .secondary)

            Text(isTargetedForDrop ? "Drop video files here" : "No Wallpapers in Library")
                .font(.title3.bold())

            Text("Drag and drop MP4 or MOV video files here,\nor click Import Video to add your desktop wallpapers.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                selectAndImportFiles()
            }) {
                Label("Import Video Files...", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func selectAndImportFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = "Select Video Wallpapers"
        panel.prompt = "Import"

        var allowed: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        if let mp4 = UTType(filenameExtension: "mp4") { allowed.append(mp4) }
        if let mov = UTType(filenameExtension: "mov") { allowed.append(mov) }
        if let m4v = UTType(filenameExtension: "m4v") { allowed.append(m4v) }
        panel.allowedContentTypes = allowed

        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let selectedURLs = panel.urls
            self.isImporting = true

            Task {
                var firstError: String? = nil
                for url in selectedURLs {
                    do {
                        _ = try await self.store.importVideo(from: url)
                    } catch {
                        firstError = error.localizedDescription
                    }
                }

                await MainActor.run {
                    self.isImporting = false
                    if let err = firstError {
                        self.errorMessage = err
                        self.showErrorAlert = true
                    }
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        Task {
            for provider in providers {
                if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil),
                   let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    do {
                        _ = try await store.importVideo(from: url)
                    } catch {
                        await MainActor.run {
                            errorMessage = error.localizedDescription
                            showErrorAlert = true
                        }
                    }
                }
            }
        }
        return true
    }
}

/// Card component representing an individual wallpaper in the library grid.
struct WallpaperCard: View {
    let wallpaper: Wallpaper
    @ObservedObject var appState: AppState
    @ObservedObject private var screenSaverManager = ScreenSaverManager.shared
    let isActive: Bool
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail container
            ZStack(alignment: .topTrailing) {
                thumbnailImage
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Active Pill (top-left)
                if isActive {
                    VStack {
                        HStack {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.green.opacity(0.8), lineWidth: 1))
                            .padding(8)

                            Spacer()
                        }
                        Spacer()
                    }
                }

                // Resolution Badge (top-right)
                Text(wallpaper.resolutionLabel)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(8)

                // Bottom gradient with duration
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(wallpaper.formattedDuration)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }
            }
            .frame(height: 140)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                // Double click card to immediately set and apply
                appState.setWallpaperForAllDisplays(wallpaper)
            }

            // Title and Details
            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(wallpaper.formattedFileSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Action Buttons
            HStack(spacing: 6) {
                // 1-Click Primary "Apply to Desktop" Button
                Button(action: {
                    appState.setWallpaperForAllDisplays(wallpaper)
                }) {
                    Label(isActive ? "Active" : "Apply", systemImage: isActive ? "checkmark.circle.fill" : "play.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? Color.green : Color.accentColor)
                .controlSize(.small)

                // Optional multi-display selector if more than 1 display connected
                if appState.displayManager.displays.count > 1 {
                    Menu {
                        ForEach(appState.displayManager.displays) { display in
                            Button("Set on \(display.name)") {
                                appState.setWallpaper(wallpaper, forDisplayID: display.id)
                            }
                        }
                    } label: {
                        Image(systemName: "display")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                // Context Actions
                Menu {
                    Button("Set to All Screens") {
                        appState.setWallpaperForAllDisplays(wallpaper)
                    }

                    if appState.displayManager.displays.count > 1 {
                        ForEach(appState.displayManager.displays) { display in
                            Button("Set on \(display.name) Only") {
                                appState.setWallpaper(wallpaper, forDisplayID: display.id)
                            }
                        }
                    }

                    Button("Set to Lock Screen") {
                        appState.setLockScreen(wallpaper)
                    }
                    .disabled(screenSaverManager.lockScreenJobPhase.isRunning)

                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([wallpaper.fileURL])
                    }

                    Divider()

                    Button(role: .destructive) {
                        appState.store.removeWallpaper(id: wallpaper.id)
                    } label: {
                        Label("Delete Wallpaper", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isActive ? Color.green.opacity(0.6) : (isHovering ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1)), lineWidth: isActive ? 2.0 : 1.5)
                )
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let path = wallpaper.thumbnailPath,
           let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [Color.indigo.opacity(0.4), Color.purple.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: "film")
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.5))
            )
        }
    }
}
