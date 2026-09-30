import UIKit
import Photos
import AVFoundation

public final class StitchEngine {

    public static let shared = StitchEngine()

    private init() {}

    /// Stitches all frames in a CaptureSession into a single seamless long image
    public func stitchSession(session: CaptureSession, dirURL: URL) async -> UIImage? {
        guard !session.frames.isEmpty else { return nil }

        // Load first frame to determine true resolution
        let firstFrameURL = dirURL.appendingPathComponent(session.frames[0].filename)
        guard let firstImage = UIImage(contentsOfFile: firstFrameURL.path)?.cgImage else {
            return nil
        }

        let width = firstImage.width
        let height = firstImage.height

        let topCrop = Int(CGFloat(height) * CGFloat(session.topMarginRatio))
        let bottomCrop = Int(CGFloat(height) * CGFloat(session.bottomMarginRatio))

        // Compute total canvas height
        var totalOffset: CGFloat = 0
        for i in 1..<session.frames.count {
            totalOffset += session.frames[i].offsetY
        }

        let totalCanvasHeight = height + Int(totalOffset) - bottomCrop
        guard totalCanvasHeight > 0 && width > 0 else { return nil }

        // Create Core Graphics Bitmap Context
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

        // Core Graphics has (0,0) at bottom-left, flip coordinates so (0,0) is top-left
        context.translateBy(x: 0, y: CGFloat(totalCanvasHeight))
        context.scaleBy(x: 1.0, y: -1.0)

        // Draw initial frame (excluding bottom home bar)
        let firstFrameRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(firstImage, in: firstFrameRect)

        // Sequentially draw new exposed content from following frames
        var currentY: CGFloat = CGFloat(height - bottomCrop)

        for i in 1..<session.frames.count {
            let record = session.frames[i]
            let deltaY = record.offsetY
            let frameURL = dirURL.appendingPathComponent(record.filename)

            guard let frameImg = UIImage(contentsOfFile: frameURL.path)?.cgImage else {
                continue
            }

            // Extract the newly exposed strip from the bottom of the content area
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

    /// Saves an image to the iOS System Photo Library with authorization check
    public func saveToPhotos(image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(
                domain: "com.fu5502.diypic",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "未获得访问相册的权限，请在系统设置中允许 diypic 访问相册"]
            )
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

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

                // Throttle frames
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
