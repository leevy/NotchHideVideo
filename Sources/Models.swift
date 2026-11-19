import AppKit
import CoreGraphics

enum WallpaperKind: String {
    case aerialVideo = "Dynamic Video (Aerial)"
    case image = "Image Wallpaper"
    case unknown = "System Default / Other"
}

struct ResolvedWallpaper {
    let kind: WallpaperKind
    let screenName: String
    let displayUUID: String?
    let assetID: String?
    let displayTitle: String?
    let fileURL: URL?
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let num = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return num.uint32Value
    }

    var displayUUID: String? {
        guard let id = displayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var menuBarStripHeight: CGFloat {
        if safeAreaInsets.top > 0 {
            return safeAreaInsets.top
        }
        let visibleGap = frame.maxY - visibleFrame.maxY
        if visibleGap > 0 {
            return visibleGap
        }
        return max(NSStatusBar.system.thickness, 24)
    }
}