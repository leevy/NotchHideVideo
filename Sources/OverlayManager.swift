import AppKit
import CoreGraphics

final class UnconstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayManager {
    private var windowsByDisplayID: [CGDirectDisplayID: UnconstrainedWindow] = [:]

    var isEnabled: Bool = true {
        didSet { updateAll() }
    }

    var builtInNotchOnly: Bool = false {
        didSet { updateAll() }
    }

    var hideWhenMenuTextIsDark: Bool = false {
        didSet { updateAll() }
    }

    private let spaceMonitor: DisplaySpaceMonitor

    init(spaceMonitor: DisplaySpaceMonitor) {
        self.spaceMonitor = spaceMonitor
    }

    func updateAll(menuBarIsDrawingDarkText: Bool = false) {
        let activeScreens = NSScreen.screens
        var activeIDs = Set<CGDirectDisplayID>()
        let spaceState = spaceMonitor.currentState()

        for screen in activeScreens {
            guard let displayID = screen.displayID else { continue }
            activeIDs.insert(displayID)

            let window = windowsByDisplayID[displayID] ?? makeOverlayWindow(for: screen)
            windowsByDisplayID[displayID] = window

            let height = screen.menuBarStripHeight
            let targetRect = NSRect(
                x: screen.frame.minX,
                y: screen.frame.maxY - height,
                width: screen.frame.width,
                height: height
            )
            if window.frame != targetRect {
                window.setFrame(targetRect, display: true)
            }

            let uuid = screen.displayUUID
            let inFullScreen = (uuid.map { spaceState.fullScreenIdentifiers.contains($0) } ?? false)
                || spaceState.fullScreenIdentifiers.contains("Main")

            let shouldSkipNotchless = builtInNotchOnly && screen.safeAreaInsets.top <= 0
            let shouldSkipDarkText = hideWhenMenuTextIsDark && menuBarIsDrawingDarkText
            let shouldShow = isEnabled && !inFullScreen && !shouldSkipNotchless && !shouldSkipDarkText

            if shouldShow {
                window.orderFrontRegardless()
            } else {
                window.orderOut(nil)
            }
        }

        for (id, window) in windowsByDisplayID where !activeIDs.contains(id) {
            window.orderOut(nil)
            windowsByDisplayID.removeValue(forKey: id)
        }
    }

    private func makeOverlayWindow(for screen: NSScreen) -> UnconstrainedWindow {
        let height = screen.menuBarStripHeight
        let rect = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - height,
            width: screen.frame.width,
            height: height
        )

        let window = UnconstrainedWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        return window
    }
}