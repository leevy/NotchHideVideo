import AppKit
import CoreGraphics

final class WallpaperResolver {
    private let fm = FileManager.default

    private var indexPlistURL: URL {
        fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    private var userAerialVideosDir: URL {
        fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos")
    }

    private var userEntriesJSONURL: URL {
        fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json")
    }

    private var legacyAerialVideosDir: URL {
        URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS")
    }

    private var legacyEntriesJSONURL: URL {
        URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/entries.json")
    }

    func resolve(for screen: NSScreen, spaceState: DisplaySpaceState) -> ResolvedWallpaper {
        let displayUUID = screen.displayUUID
        let spaceUUID = displayUUID.flatMap { spaceState.currentSpaceUUIDByDisplay[$0] }
            ?? spaceState.currentSpaceUUIDByDisplay["Main"]

        if let data = try? Data(contentsOf: indexPlistURL),
           let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {

            let candidateNodes: [[String: Any]?] = [
                spaceUUID.flatMap { (root["Spaces"] as? [String: Any])?[$0] as? [String: Any] },
                displayUUID.flatMap { (root["Displays"] as? [String: Any])?[$0] as? [String: Any] },
                root["AllSpacesAndDisplays"] as? [String: Any],
                root["SystemDefault"] as? [String: Any]
            ]

            for case let node? in candidateNodes {
                if let resolved = parseWallpaperNode(node, screen: screen, displayUUID: displayUUID) {
                    return resolved
                }
            }
        }

        if let fallbackImageURL = NSWorkspace.shared.desktopImageURL(for: screen) {
            return ResolvedWallpaper(
                kind: .image,
                screenName: screen.localizedName,
                displayUUID: displayUUID,
                assetID: nil,
                displayTitle: fallbackImageURL.lastPathComponent,
                fileURL: fallbackImageURL
            )
        }

        return ResolvedWallpaper(
            kind: .unknown,
            screenName: screen.localizedName,
            displayUUID: displayUUID,
            assetID: nil,
            displayTitle: nil,
            fileURL: nil
        )
    }

    private func parseWallpaperNode(
        _ node: [String: Any],
        screen: NSScreen,
        displayUUID: String?
    ) -> ResolvedWallpaper? {
        let container = (node["Desktop"] as? [String: Any])
            ?? (node["Linked"] as? [String: Any])
            ?? (node["Idle"] as? [String: Any])

        guard let content = container?["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let provider = firstChoice["Provider"] as? String else {
            return nil
        }

        var assetID: String?
        if let configData = firstChoice["Configuration"] as? Data,
           let config = try? PropertyListSerialization.propertyList(from: configData, options: [], format: nil) as? [String: Any] {
            assetID = config["assetID"] as? String
        }

        if provider == "com.apple.wallpaper.choice.aerials" {
            if assetID == "shuffle-all-aerials" {
                return ResolvedWallpaper(
                    kind: .aerialVideo,
                    screenName: screen.localizedName,
                    displayUUID: displayUUID,
                    assetID: assetID,
                    displayTitle: "Aerial Shuffle",
                    fileURL: nil
                )
            }

            if let id = assetID {
                let videoURL = locateAerialVideo(assetID: id)
                let title = locateAerialTitle(assetID: id) ?? id
                return ResolvedWallpaper(
                    kind: .aerialVideo,
                    screenName: screen.localizedName,
                    displayUUID: displayUUID,
                    assetID: id,
                    displayTitle: title,
                    fileURL: videoURL
                )
            }
        }

        if let files = firstChoice["Files"] as? [[String: Any]],
           let relative = files.first?["relative"] as? String,
           let url = URL(string: relative), url.isFileURL {
            return ResolvedWallpaper(
                kind: .image,
                screenName: screen.localizedName,
                displayUUID: displayUUID,
                assetID: assetID,
                displayTitle: url.lastPathComponent,
                fileURL: url
            )
        }

        return nil
    }

    private func locateAerialVideo(assetID: String) -> URL? {
        let directCandidates = [
            userAerialVideosDir.appendingPathComponent("\(assetID).mov"),
            userAerialVideosDir.appendingPathComponent("\(assetID).mp4"),
            legacyAerialVideosDir.appendingPathComponent("\(assetID).mov")
        ]
        for url in directCandidates where fm.fileExists(atPath: url.path) {
            return url
        }

        // Check entries.json in case a custom video/Solar asset points to a local file:// URL
        for manifestURL in [userEntriesJSONURL, legacyEntriesJSONURL] {
            if let asset = findManifestAsset(id: assetID, in: manifestURL) {
                for key in ["url-4K-SDR-240FPS", "url-4K-SDR", "url-1080-SDR", "url"] {
                    if let urlString = asset[key] as? String,
                       let url = URL(string: urlString),
                       url.isFileURL,
                       fm.fileExists(atPath: url.path) {
                        return url
                    }
                }
            }
        }
        return nil
    }

    private func locateAerialTitle(assetID: String) -> String? {
        for manifestURL in [userEntriesJSONURL, legacyEntriesJSONURL] {
            if let asset = findManifestAsset(id: assetID, in: manifestURL) {
                if let label = asset["accessibilityLabel"] as? String, !label.isEmpty {
                    return label
                }
                if let shotID = asset["shotID"] as? String, !shotID.isEmpty {
                    return shotID
                }
            }
        }
        return nil
    }

    private func findManifestAsset(id: String, in jsonURL: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: jsonURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            return nil
        }
        return assets.first { ($0["id"] as? String)?.caseInsensitiveCompare(id) == .orderedSame }
    }
}