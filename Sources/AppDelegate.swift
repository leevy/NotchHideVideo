import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let spaceMonitor = DisplaySpaceMonitor()
    private let resolver = WallpaperResolver()
    private let patcher = VideoPatcher()
    private lazy var overlayManager = OverlayManager(spaceMonitor: spaceMonitor)

    private var statusItem: NSStatusItem!
    private var appearanceObservation: NSKeyValueObservation?
    private var isPatching = false
    private var patchProgressText: String?

    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled",
                accessibilityDescription: "NotchHideVideo"
            )
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refreshOverlays()
                }
            }
        }

        menu.delegate = self
        statusItem.menu = menu

        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleEnvironmentChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleEnvironmentChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        refreshOverlays()
    }

    @objc private func handleEnvironmentChange() {
        refreshOverlays()
        // Space transitions animate for ~0.4s before Current Space settles
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            self.refreshOverlays()
        }
    }

    private var menuBarIsDrawingDarkText: Bool {
        guard let appearance = statusItem.button?.effectiveAppearance else { return false }
        return appearance.bestMatch(from: [.vibrantDark, .vibrantLight]) == .vibrantLight
    }

    private func refreshOverlays() {
        overlayManager.updateAll(menuBarIsDrawingDarkText: menuBarIsDrawingDarkText)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let spaceState = spaceMonitor.currentState()
        let activeScreen = NSScreen.main ?? NSScreen.screens.first
        let resolved = activeScreen.map { resolver.resolve(for: $0, spaceState: spaceState) }

        let overlayToggle = NSMenuItem(
            title: "Enable Black Menu Bar Overlay",
            action: #selector(toggleOverlay),
            keyEquivalent: ""
        )
        overlayToggle.state = overlayManager.isEnabled ? .on : .off
        menu.addItem(overlayToggle)

        let notchOnlyToggle = NSMenuItem(
            title: "Notched Display Only",
            action: #selector(toggleNotchOnly),
            keyEquivalent: ""
        )
        notchOnlyToggle.state = overlayManager.builtInNotchOnly ? .on : .off
        menu.addItem(notchOnlyToggle)

        let autoHideDarkTextToggle = NSMenuItem(
            title: "Auto-Hide When Menu Text Is Black",
            action: #selector(toggleAutoHideDarkText),
            keyEquivalent: ""
        )
        autoHideDarkTextToggle.state = overlayManager.hideWhenMenuTextIsDark ? .on : .off
        menu.addItem(autoHideDarkTextToggle)

        if menuBarIsDrawingDarkText {
            let warnItem = NSMenuItem(
                title: "⚠ Light Wallpaper: Menu Text Is Black",
                action: nil,
                keyEquivalent: ""
            )
            warnItem.isEnabled = false
            menu.addItem(warnItem)
        }

        menu.addItem(.separator())

        if let resolved {
            let infoHeader = NSMenuItem(
                title: "Active: \(resolved.kind.rawValue)",
                action: nil,
                keyEquivalent: ""
            )
            infoHeader.isEnabled = false
            menu.addItem(infoHeader)

            if let title = resolved.displayTitle {
                let titleItem = NSMenuItem(title: "  Source: \(title)", action: nil, keyEquivalent: "")
                titleItem.isEnabled = false
                menu.addItem(titleItem)
            }
        }

        if let patchProgressText {
            let progItem = NSMenuItem(title: patchProgressText, action: nil, keyEquivalent: "")
            progItem.isEnabled = false
            menu.addItem(progItem)
        } else {
            let patchFrameItem = NSMenuItem(
                title: "Apply Patched Still Frame (Forces White Text)",
                action: #selector(patchCurrentFrame),
                keyEquivalent: ""
            )
            patchFrameItem.isEnabled = !isPatching && (resolved?.fileURL != nil)
            menu.addItem(patchFrameItem)

            let patchVideoItem = NSMenuItem(
                title: "Bake Black Bar Into Dynamic Video (.mov)…",
                action: #selector(patchDynamicVideo),
                keyEquivalent: ""
            )
            let isAerialFile = (resolved?.kind == .aerialVideo) && (resolved?.fileURL != nil)
            patchVideoItem.isEnabled = !isPatching && isAerialFile
            menu.addItem(patchVideoItem)
        }

        let restoreItem = NSMenuItem(
            title: "Restore Original Dynamic Wallpaper",
            action: #selector(restoreWallpaper),
            keyEquivalent: ""
        )
        restoreItem.isEnabled = !isPatching && patcher.hasBackup
        menu.addItem(restoreItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleOverlay() {
        overlayManager.isEnabled.toggle()
        refreshOverlays()
    }

    @objc private func toggleNotchOnly() {
        overlayManager.builtInNotchOnly.toggle()
        refreshOverlays()
    }

    @objc private func toggleAutoHideDarkText() {
        overlayManager.hideWhenMenuTextIsDark.toggle()
        refreshOverlays()
    }

    @objc private func patchCurrentFrame() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let resolved = resolver.resolve(for: screen, spaceState: spaceMonitor.currentState())
        guard let fileURL = resolved.fileURL else { return }

        isPatching = true
        patchProgressText = "Extracting & patching frame…"

        Task {
            do {
                _ = try await patcher.applyPatchedFrame(from: fileURL, to: screen)
            } catch {
                showError(error)
            }
            isPatching = false
            patchProgressText = nil
            refreshOverlays()
        }
    }

    @objc private func patchDynamicVideo() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let resolved = resolver.resolve(for: screen, spaceState: spaceMonitor.currentState())
        guard let fileURL = resolved.fileURL else { return }

        let screenSize = screen.frame.size
        let barHeight = screen.menuBarStripHeight

        isPatching = true
        patchProgressText = "Baking black bar into video (0%)…"

        Task {
            do {
                try await patcher.patchCachedAerialVideo(
                    sourceURL: fileURL,
                    screenSize: screenSize,
                    menuBarHeight: barHeight
                ) { pct in
                    Task { @MainActor in
                        self.patchProgressText = "Baking black bar into video (\(Int(pct * 100))%)…"
                    }
                }
            } catch {
                showError(error)
            }
            isPatching = false
            patchProgressText = nil
            refreshOverlays()
        }
    }

    @objc private func restoreWallpaper() {
        do {
            try patcher.restoreOriginal()
            refreshOverlays()
        } catch {
            showError(error)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "NotchHideVideo"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}