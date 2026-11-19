import AppKit
import CoreGraphics
import Darwin

struct DisplaySpaceState {
    let fullScreenIdentifiers: Set<String>
    let currentSpaceUUIDByDisplay: [String: String]
}

final class DisplaySpaceMonitor {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private let mainConnection: MainConnectionFn?
    private let copyManagedSpaces: CopyManagedDisplaySpacesFn?

    init() {
        let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
        if let handle,
           let mainSym = dlsym(handle, "CGSMainConnectionID"),
           let spacesSym = dlsym(handle, "CGSCopyManagedDisplaySpaces") {
            mainConnection = unsafeBitCast(mainSym, to: MainConnectionFn.self)
            copyManagedSpaces = unsafeBitCast(spacesSym, to: CopyManagedDisplaySpacesFn.self)
        } else {
            mainConnection = nil
            copyManagedSpaces = nil
        }
    }

    func currentState() -> DisplaySpaceState {
        guard let mainConnection, let copyManagedSpaces,
              let rawArray = copyManagedSpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else {
            return DisplaySpaceState(fullScreenIdentifiers: [], currentSpaceUUIDByDisplay: [:])
        }

        var fullScreenIDs = Set<String>()
        var spaceUUIDs: [String: String] = [:]

        for entry in rawArray {
            guard let identifier = entry["Display Identifier"] as? String,
                  let current = entry["Current Space"] as? [String: Any] else { continue }

            if let spaceType = current["type"] as? Int, spaceType == 4 {
                fullScreenIDs.insert(identifier)
            }
            if let uuid = current["uuid"] as? String {
                spaceUUIDs[identifier] = uuid
            }
        }

        return DisplaySpaceState(
            fullScreenIdentifiers: fullScreenIDs,
            currentSpaceUUIDByDisplay: spaceUUIDs
        )
    }
}