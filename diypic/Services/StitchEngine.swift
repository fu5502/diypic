import UIKit
import Photos
import AVFoundation

public final class StitchEngine {

    public static let shared = StitchEngine()

    private init() {}

    // MARK: - 1. CaptureSession Stitching (from Broadcast Extension)

    /// Stitches all frames in a CaptureSession into a single seamless long image
    public func stitchSession(session: CaptureSession, dirURL: URL) async -> UIImage? {
        guard !session.frames.isEmpty else { return nil }

        let firstFrameURL = dirURL.appendingPathComponent(session.frames[0].filename)
        guard let firstImage = UIImage(contentsOfFile: firstFrameURL.path)?.cgImage else {
            return nil
        }

        let width = firstImage.width
        let height = firstImage.height

        let topCrop = Int(CGFloat(height) * CGFloat(session.topMarginRatio))
        let bottomCrop = Int(CGFloat(height) * CGFloat(session.bottomMarginRatio))

        var totalOffset: CGFloat = 0
        for i in 1..<session.frames.count {
            totalOffset += session.frames[i].offsetY
        }

        let totalCanvasHeight = height + Int(totalOffset) - bottomCrop
        guard totalCanvasHeight > 0 && width > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: totalCanvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        context.translateBy(x: 0, y: CGFloat(totalCanvasHeight))
        context.scaleBy(x: 1.0, y: -1.0)

        // Draw initial frame
        let firstFrameRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(firstImage, in: firstFrameRect)

        var currentY: CGFloat = CGFloat(height - bottomCrop)

        for i in 1..<session.frames.count {
            let record = session.frames[i]
            let deltaY = record.offsetY
            let frameURL = dirURL.appendingPathComponent(record.filename)

            guard let frameImg = UIImage(contentsOfFile: frameURL.path)?.cgImage else {
                continue
            }

            let stripSourceY = height - bottomCrop - Int(deltaY)
            if stripSourceY >= topCrop && Int(deltaY) > 0 {
                let cropRect = CGRect(
                    x: 0,
                    y: stripSourceY,
                    width: width,
                    height: Int(deltaY)
                )

                if let croppedStrip = frameImg.cropping(to: cropRect) {
                    let destRect = CGRect(
                        x: 0,
                        y: currentY,
                        width: CGFloat(width),
                        height: deltaY
                    )
                    context.draw(croppedStrip, in: destRect)
                    currentY += deltaY
                }
            }
        }

        guard let outputCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: outputCGImage)
    }

    // MARK: - 2. Multiple Screenshots Stitching (Smart Overlap Elimination)

    /// Seamlessly stitches multiple overlapping screenshots by auto-detecting vertical overlaps
    public func stitchMultipleImages(images: [UIImage], removeOverlap: Bool = true) async -> UIImage? {
        guard !images.isEmpty else { return nil }
        guard images.count > 1 else { return images.first }

        // Normalize images to same pixel width based on first image
        guard let firstCG = images[0].cgImage else { return nil }
        let targetWidth = firstCG.width

        var normalizedCGs: [CGImage] = []
        for img in images {
            if let cg = img.cgImage {
                if cg.width == targetWidth {
                    normalizedCGs.append(cg)
                } else {
                    // Resize to match width
                    let scale = CGFloat(targetWidth) / CGFloat(cg.width)
                    let newH = Int(CGFloat(cg.height) * scale)
                    if let resized = resizeCGImage(cg, targetWidth: targetWidth, targetHeight: newH) {
                        normalizedCGs.append(resized)
                    } else {
                        normalizedCGs.append(cg)
                    }
                }
            }
        }

        guard normalizedCGs.count == images.count else { return nil }

        if !removeOverlap {
            // Simple sequential vertical stacking
            let totalHeight = normalizedCGs.reduce(0) { $0 + $1.height }
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil,
                width: targetWidth,
                height: totalHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).rawValue
            ) else { return nil }

            ctx.translateBy(x: 0, y: CGFloat(totalHeight))
            ctx.scaleBy(x: 1.0, y: -1.0)

            var drawY: CGFloat = 0
            for cg in normalizedCGs {
                ctx.draw(cg, in: CGRect(x: 0, y: Int(drawY), width: targetWidth, height: cg.height))
                drawY += CGFloat(cg.height)
            }
            guard let outImg = ctx.makeImage() else { return nil }
            return UIImage(cgImage: outImg)
        }

        // Smart Overlap Stitching
        // For each pair (image[i], image[i+1]), find best vertical overlap
        struct StitchStep {
            let nextImage: CGImage
            let cutTopInNext: Int // How many pixels to skip from top of next image
        }

        var steps: [StitchStep] = []

        for i in 0..<(normalizedCGs.count - 1) {
            let imgA = normalizedCGs[i]
            let imgB = normalizedCGs[i + 1]

            let overlap = findBestVerticalOverlap(topImage: imgA, bottomImage: imgB)
            steps.append(StitchStep(nextImage: imgB, cutTopInNext: overlap))
        }

        // Compute total canvas height
        var totalCanvasHeight = normalizedCGs[0].height
        for step in steps {
            let addedHeight = step.nextImage.height - step.cutTopInNext
            if addedHeight > 0 {
                totalCanvasHeight += addedHeight
            }
        }

        guard totalCanvasHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: totalCanvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).rawValue
        ) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(totalCanvasHeight))
        ctx.scaleBy(x: 1.0, y: -1.0)

        // Draw base image
        ctx.draw(normalizedCGs[0], in: CGRect(x: 0, y: 0, width: targetWidth, height: normalizedCGs[0].height))

        var currentY = CGFloat(normalizedCGs[0].height)

        for step in steps {
            let addedHeight = step.nextImage.height - step.cutTopInNext
            guard addedHeight > 0 else { continue }

            let cropRect = CGRect(
                x: 0,
                y: step.cutTopInNext,
                width: targetWidth,
                height: addedHeight
            )

            if let cropped = step.nextImage.cropping(to: cropRect) {
                ctx.draw(cropped, in: CGRect(x: 0, y: Int(currentY), width: targetWidth, height: addedHeight))
                currentY += CGFloat(addedHeight)
            }
        }

        guard let output = ctx.makeImage() else { return nil }
        return UIImage(cgImage: output)
    }

    /// Finds vertical overlap between the bottom of topImage and the top of bottomImage using correlation
    private func findBestVerticalOverlap(topImage: CGImage, bottomImage: CGImage) -> Int {
        let width = topImage.width
        let heightA = topImage.height
        let heightB = bottomImage.height

        // Downsample horizontal strip to 64 columns for fast matching
        let sampleCols = 64
        let stepX = max(1, width / sampleCols)

        // Search candidate overlap heights: from 5% to 85% of image height
        let minOverlap = Int(Double(min(heightA, heightB)) * 0.05)
        let maxOverlap = Int(Double(min(heightA, heightB)) * 0.85)

        // Extract grayscale rows
        let rowsA = extractSampledGrayscaleRows(from: topImage, sampleCols: sampleCols, stepX: stepX)
        let rowsB = extractSampledGrayscaleRows(from: bottomImage, sampleCols: sampleCols, stepX: stepX)

        guard !rowsA.isEmpty && !rowsB.isEmpty else { return 0 }

        var bestOverlap = 0
        var bestDiff: Double = Double.greatestFiniteMagnitude

        // Template comparison window: compare up to 60 rows
        let checkRows = 40
        let searchStep = 2 // step by 2 pixels for speed

        for overlap in stride(from: minOverlap, through: maxOverlap, by: searchStep) {
            if overlap >= heightA || overlap >= heightB { break }

            var diffSum: Double = 0
            var count = 0

            let compareCount = min(checkRows, overlap)
            for r in 0..<compareCount {
                let rowIdxA = heightA - overlap + r
                let rowIdxB = r
                if rowIdxA >= heightA || rowIdxB >= heightB { continue }

                let offsetA = rowIdxA * sampleCols
                let offsetB = rowIdxB * sampleCols

                for c in 0..<sampleCols {
                    let vA = Double(rowsA[offsetA + c])
                    let vB = Double(rowsB[offsetB + c])
                    diffSum += abs(vA - vB)
                    count += 1
                }
            }

            if count > 0 {
                let avgDiff = diffSum / Double(count)
                if avgDiff < bestDiff {
                    bestDiff = avgDiff
                    bestOverlap = overlap
                }
            }
        }

        // If average pixel difference is too high (poor match), fallback to 0 overlap
        if bestDiff > 45.0 {
            return 0
        }

        return bestOverlap
    }

    private func extractSampledGrayscaleRows(from image: CGImage, sampleCols: Int, stepX: Int) -> [UInt8] {
        let w = image.width
        let h = image.height
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return []
        }

        let bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        var result = [UInt8](repeating: 0, count: h * sampleCols)

        for y in 0..<h {
            let rowStart = y * bpr
            let outRowOffset = y * sampleCols
            for col in 0..<sampleCols {
                let x = min(w - 1, col * stepX)
                let pOffset = rowStart + x * bpp
                let r = Double(ptr[pOffset])
                let g = Double(ptr[pOffset + 1])
                let b = Double(ptr[pOffset + 2])
                let gray = UInt8(r * 0.299 + g * 0.587 + b * 0.114)
                result[outRowOffset + col] = gray
            }
        }
        return result
    }

    private func resizeCGImage(_ image: CGImage, targetWidth: Int, targetHeight: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return ctx.makeImage()
    }

    // MARK: - 3. Save to Photos

    /// Saves an image to the iOS System Photo Library with authorization check
    public func saveToPhotos(image: UIImage) async throws {
        var currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if currentStatus == .notDetermined {
            currentStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }

        guard currentStatus == .authorized || currentStatus == .limited else {
            throw NSError(
                domain: "com.fu5502.diypic",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "未获得相册访问权限，请在系统「设置 -> diypic -> 照片」中勾选「全部照片」"]
            )
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }

        await MainActor.run {
            PhotoPermissionManager.shared.checkStatus()
        }
    }

    // MARK: - 4. Video to Long Screenshot

    /// Fallback: stitches a screen-recording MP4 video directly from Photo Library into a long image
    public func stitchFromVideo(videoURL: URL, progress: @escaping (Float) -> Void) async -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(trackOutput)
        reader.startReading()

        let estimator = MotionEstimator()
        var frames: [(image: CGImage, deltaY: CGFloat)] = []
        var frameIndex = 0

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            autoreleasepool {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

                if frameIndex % 3 == 0 {
                    if let estimate = estimator.estimateOffset(pixelBuffer: pixelBuffer) {
                        if estimate.offsetY >= estimator.minScrollPixelThreshold || frames.isEmpty {
                            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                            let ciContext = CIContext()
                            if let cg = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                                frames.append((image: cg, deltaY: estimate.offsetY))
                            }
                        }
                    }
                }
                frameIndex += 1
            }
        }

        guard !frames.isEmpty else { return nil }

        let width = frames[0].image.width
        let height = frames[0].image.height
        let bottomCrop = Int(CGFloat(height) * estimator.bottomMarginRatio)
        let topCrop = Int(CGFloat(height) * estimator.topMarginRatio)

        var totalOffset: CGFloat = 0
        for i in 1..<frames.count {
            totalOffset += frames[i].deltaY
        }

        let totalCanvasHeight = height + Int(totalOffset) - bottomCrop
        guard totalCanvasHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: totalCanvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).rawValue
        ) else {
            return nil
        }

        context.translateBy(x: 0, y: CGFloat(totalCanvasHeight))
        context.scaleBy(x: 1.0, y: -1.0)

        // Draw first frame
        context.draw(frames[0].image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var currentY: CGFloat = CGFloat(height - bottomCrop)
        for i in 1..<frames.count {
            let deltaY = frames[i].deltaY
            let stripSourceY = height - bottomCrop - Int(deltaY)
            if stripSourceY >= topCrop && Int(deltaY) > 0 {
                let cropRect = CGRect(x: 0, y: stripSourceY, width: width, height: Int(deltaY))
                if let strip = frames[i].image.cropping(to: cropRect) {
                    context.draw(strip, in: CGRect(x: 0, y: currentY, width: CGFloat(width), height: deltaY))
                    currentY += deltaY
                }
            }
        }

        guard let output = context.makeImage() else { return nil }
        return UIImage(cgImage: output)
    }
}
