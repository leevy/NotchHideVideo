import AppKit
import AVFoundation
import CoreImage
import Darwin
import UniformTypeIdentifiers
import VideoToolbox

enum PatchError: LocalizedError {
    case noVideoTrack
    case failedToCreateContext
    case failedToSaveImage
    case cannotWriteVideo(String)
    case noBackupFound

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "The dynamic wallpaper file has no video track."
        case .failedToCreateContext: return "Failed to allocate CoreGraphics drawing context."
        case .failedToSaveImage: return "Failed to encode patched PNG wallpaper."
        case .cannotWriteVideo(let msg): return "Video export failed: \(msg)"
        case .noBackupFound: return "No backup found to restore."
        }
    }
}

final class VideoPatcher {
    private let fm = FileManager.default

    private var appSupportDir: URL {
        let dir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchHideVideo", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var backupsDir: URL {
        let dir = appSupportDir.appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexPlistURL: URL {
        fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    var hasBackup: Bool {
        let plistBackup = backupsDir.appendingPathComponent("Index.plist.bak")
        if fm.fileExists(atPath: plistBackup.path) { return true }
        let files = (try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)) ?? []
        return files.contains { $0.pathExtension == "mov" || $0.pathExtension == "mp4" }
    }

    func applyPatchedFrame(from videoURL: URL, to screen: NSScreen) async throws -> URL {
        backupIndexPlistIfNeeded()

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let cgFrame = try await generator.image(at: .zero).image
        let scale = screen.backingScaleFactor
        let pixelW = Int((screen.frame.width * scale).rounded())
        let pixelH = Int((screen.frame.height * scale).rounded())
        let barPx = (screen.menuBarStripHeight * scale).rounded()

        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PatchError.failedToCreateContext
        }

        let srcW = CGFloat(cgFrame.width)
        let srcH = CGFloat(cgFrame.height)
        let targetW = CGFloat(pixelW)
        let targetH = CGFloat(pixelH)
        let fillScale = max(targetW / srcW, targetH / srcH)
        let drawW = srcW * fillScale
        let drawH = srcH * fillScale
        let drawRect = CGRect(
            x: (targetW - drawW) / 2.0,
            y: (targetH - drawH) / 2.0,
            width: drawW,
            height: drawH
        )

        ctx.interpolationQuality = .high
        ctx.draw(cgFrame, in: drawRect)

        // CoreGraphics origin is bottom-left, so top menu bar sits at [targetH - barPx, targetH]
        ctx.setFillColor(CGColor.black)
        ctx.fill(CGRect(x: 0, y: targetH - barPx, width: targetW, height: barPx))

        guard let outImage = ctx.makeImage() else {
            throw PatchError.failedToSaveImage
        }

        let outURL = appSupportDir.appendingPathComponent("patched_\(UUID().uuidString).png")
        guard let dest = CGImageDestinationCreateWithURL(
            outURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PatchError.failedToSaveImage
        }
        CGImageDestinationAddImage(dest, outImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw PatchError.failedToSaveImage
        }

        try await MainActor.run {
            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            try NSWorkspace.shared.setDesktopImageURL(outURL, for: screen, options: options)
        }

        return outURL
    }

    func patchCachedAerialVideo(
        sourceURL: URL,
        screenSize: CGSize,
        menuBarHeight: CGFloat,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard fm.isWritableFile(atPath: sourceURL.path) else {
            throw PatchError.cannotWriteVideo(
                "File at \(sourceURL.path) is in a system-protected folder. Only user-cached Aerials in ~/Library can be patched directly."
            )
        }

        let backupURL = backupsDir.appendingPathComponent(sourceURL.lastPathComponent)
        if !fm.fileExists(atPath: backupURL.path) {
            try fm.copyItem(at: sourceURL, to: backupURL)
        }

        let tempOut = appSupportDir.appendingPathComponent("patched_\(UUID().uuidString).mov")
        defer { try? fm.removeItem(at: tempOut) }

        try await encodeVideoWithBlackBar(
            sourceURL: backupURL,
            outputURL: tempOut,
            screenSize: screenSize,
            menuBarHeight: menuBarHeight,
            progress: progress
        )

        // Preserve original Apple extended attributes so WallpaperAgent doesn't re-download
        copyfile(backupURL.path, tempOut.path, nil, copyfile_flags_t(COPYFILE_XATTR))

        try fm.removeItem(at: sourceURL)
        try fm.moveItem(at: tempOut, to: sourceURL)
        restartWallpaperAgent()
    }

    func restoreOriginal() throws {
        var restoredAnything = false

        let plistBackup = backupsDir.appendingPathComponent("Index.plist.bak")
        if fm.fileExists(atPath: plistBackup.path) {
            if fm.fileExists(atPath: indexPlistURL.path) {
                try fm.removeItem(at: indexPlistURL)
            }
            try fm.copyItem(at: plistBackup, to: indexPlistURL)
            try? fm.removeItem(at: plistBackup)
            restoredAnything = true
        }

        let userVideosDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos")
        let backups = (try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)) ?? []
        for backup in backups where backup.pathExtension == "mov" || backup.pathExtension == "mp4" {
            let target = userVideosDir.appendingPathComponent(backup.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.moveItem(at: backup, to: target)
            restoredAnything = true
        }

        guard restoredAnything else {
            throw PatchError.noBackupFound
        }
        restartWallpaperAgent()
    }

    private func backupIndexPlistIfNeeded() {
        let backup = backupsDir.appendingPathComponent("Index.plist.bak")
        guard !fm.fileExists(atPath: backup.path),
              fm.fileExists(atPath: indexPlistURL.path) else { return }
        try? fm.copyItem(at: indexPlistURL, to: backup)
    }

    private func restartWallpaperAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        try? task.run()
    }

    private func encodeVideoWithBlackBar(
        sourceURL: URL,
        outputURL: URL,
        screenSize: CGSize,
        menuBarHeight: CGFloat,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw PatchError.noVideoTrack
        }

        let naturalSize = try await track.load(.naturalSize)
        let nominalFPS = try await track.load(.nominalFrameRate)
        let durationSeconds = max(try await asset.load(.duration).seconds, 0.001)

        let evenWidth = max(Int(naturalSize.width) & ~1, 2)
        let evenHeight = max(Int(naturalSize.height) & ~1, 2)
        let renderSize = CGSize(width: evenWidth, height: evenHeight)

        // Calculate top black strip height in video pixels matching macOS aspect-fill crop
        let videoAspect = renderSize.width / renderSize.height
        let screenAspect = screenSize.width / max(screenSize.height, 1)
        let barFraction = menuBarHeight / max(screenSize.height, 1)
        let barPx: CGFloat
        if videoAspect >= screenAspect {
            barPx = renderSize.height * barFraction
        } else {
            let visibleHeight = renderSize.width / screenAspect
            let topCrop = (renderSize.height - visibleHeight) / 2.0
            barPx = topCrop + visibleHeight * barFraction
        }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw PatchError.cannotWriteVideo("Cannot attach AVAssetReaderTrackOutput.")
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let compressionProps: [String: Any] = [
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
            kVTCompressionPropertyKey_BaseLayerFrameRateFraction as String: 0.5,
            AVVideoExpectedSourceFrameRateKey: nominalFPS > 0 ? nominalFPS : 60
        ]
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: evenWidth,
                AVVideoHeightKey: evenHeight,
                AVVideoCompressionPropertiesKey: compressionProps
            ]
        )
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: evenWidth,
                kCVPixelBufferHeightKey as String: evenHeight
            ]
        )

        guard writer.canAdd(writerInput) else {
            throw PatchError.cannotWriteVideo("Cannot attach HEVC AVAssetWriterInput.")
        }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw PatchError.cannotWriteVideo(reader.error?.localizedDescription ?? "Reader failed.")
        }
        guard writer.startWriting() else {
            throw PatchError.cannotWriteVideo(writer.error?.localizedDescription ?? "Writer failed.")
        }
        writer.startSession(atSourceTime: .zero)

        let ciContext = CIContext(options: [.cacheIntermediates: false])
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let extent = CGRect(origin: .zero, size: renderSize)
        let blackBarImage = CIImage(color: .black).cropped(
            to: CGRect(x: 0, y: extent.height - barPx, width: extent.width, height: barPx)
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let encodeQueue = DispatchQueue(label: "local.notchhide.video.encode")
            var isDone = false

            writerInput.requestMediaDataWhenReady(on: encodeQueue) {
                while writerInput.isReadyForMoreMediaData && !isDone {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        guard let srcBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                              let pool = adaptor.pixelBufferPool else { continue }

                        var dstBufferOpt: CVPixelBuffer?
                        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &dstBufferOpt) == kCVReturnSuccess,
                              let dstBuffer = dstBufferOpt else { continue }

                        autoreleasepool {
                            let srcCI = CIImage(cvPixelBuffer: srcBuffer)
                            let composited = blackBarImage.composited(over: srcCI)
                            ciContext.render(composited, to: dstBuffer, bounds: extent, colorSpace: colorSpace)
                        }

                        adaptor.append(dstBuffer, withPresentationTime: pts)
                        progress(min(max(pts.seconds / durationSeconds, 0), 1))
                    } else {
                        isDone = true
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if let err = writer.error ?? reader.error {
                                continuation.resume(throwing: err)
                            } else {
                                progress(1.0)
                                continuation.resume()
                            }
                        }
                    }
                }
            }
        }
    }
}