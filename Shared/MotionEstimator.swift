import Foundation
import CoreVideo
import CoreGraphics
import Accelerate

/// Lightweight vertical motion estimator for UI scroll tracking
/// Optimized for the <50MB iOS Broadcast Upload Extension memory limit
public final class MotionEstimator {

    // Downscaled sample dimensions for ultra-fast motion estimation
    private let sampleWidth: Int = 64
    private let sampleHeight: Int = 240

    // Top and bottom margin ratios to avoid status bar and home indicator
    public var topMarginRatio: CGFloat = 0.12
    public var bottomMarginRatio: CGFloat = 0.08

    // Previous frame downsampled grayscale buffer
    private var previousBuffer: [UInt8]?

    // Minimum scroll movement in original pixel coordinates to trigger a new slice
    public let minScrollPixelThreshold: CGFloat = 12.0

    public init() {}

    public func reset() {
        previousBuffer = nil
    }

    /// Estimates the downward scroll offset (in points/pixels of the original image)
    /// Returns: (offsetY in original pixels, correlationScore: 0.0 ~ 1.0)
    public func estimateOffset(pixelBuffer: CVPixelBuffer) -> (offsetY: CGFloat, confidence: Float)? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard width > 0 && height > 0 else { return nil }

        // Calculate content area (excluding status bar and home bar)
        let topCrop = Int(CGFloat(height) * topMarginRatio)
        let bottomCrop = Int(CGFloat(height) * bottomMarginRatio)
        let contentHeight = height - topCrop - bottomCrop

        guard contentHeight > sampleHeight else { return nil }

        // Extract downscaled grayscale representation of the content area
        guard let currentBuffer = extractDownsampledGrayscale(
            from: pixelBuffer,
            cropX: width / 4,
            cropY: topCrop,
            cropWidth: width / 2,
            cropHeight: contentHeight
        ) else {
            return nil
        }

        defer {
            self.previousBuffer = currentBuffer
        }

        guard let prev = previousBuffer else {
            return (offsetY: 0, confidence: 1.0)
        }

        let maxSearchShift = sampleHeight / 3
        let templateHeight = sampleHeight / 2
        let templateStart = sampleHeight / 4

        var bestShift = 0
        var bestScore: Float = Float.greatestFiniteMagnitude

        for shift in 0...maxSearchShift {
            var diffSum: Float = 0
            var count: Int = 0

            for y in 0..<templateHeight {
                let prevY = templateStart + y
                let currY = templateStart + y - shift
                if currY < 0 { continue }

                let prevRowOffset = prevY * sampleWidth
                let currRowOffset = currY * sampleWidth

                for x in stride(from: 0, to: sampleWidth, by: 2) {
                    let pVal = Float(prev[prevRowOffset + x])
                    let cVal = Float(currentBuffer[currRowOffset + x])
                    diffSum += abs(pVal - cVal)
                    count += 1
                }
            }

            if count > 0 {
                let avgDiff = diffSum / Float(count)
                if avgDiff < bestScore {
                    bestScore = avgDiff
                    bestShift = shift
                }
            }
        }

        let confidence = max(0.0, 1.0 - (bestScore / 128.0))
        let scaleFactor = CGFloat(contentHeight) / CGFloat(sampleHeight)
        let originalOffsetY = CGFloat(bestShift) * scaleFactor

        return (offsetY: originalOffsetY, confidence: confidence)
    }

    private func extractDownsampledGrayscale(
        from pixelBuffer: CVPixelBuffer,
        cropX: Int,
        cropY: Int,
        cropWidth: Int,
        cropHeight: Int
    ) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        var result = [UInt8](repeating: 0, count: sampleWidth * sampleHeight)

        let stepX = Double(cropWidth) / Double(sampleWidth)
        let stepY = Double(cropHeight) / Double(sampleHeight)

        if pixelFormat == kCVPixelFormatType_32BGRA {
            let bufferPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
            for dy in 0..<sampleHeight {
                let sy = cropY + Int(Double(dy) * stepY)
                let rowStart = sy * bytesPerRow
                for dx in 0..<sampleWidth {
                    let sx = cropX + Int(Double(dx) * stepX)
                    let pixelOffset = rowStart + sx * 4
                    let b = bufferPtr[pixelOffset]
                    let g = bufferPtr[pixelOffset + 1]
                    let r = bufferPtr[pixelOffset + 2]
                    let gray = UInt8((UInt32(r) * 77 + UInt32(g) * 150 + UInt32(b) * 29) >> 8)
                    result[dy * sampleWidth + dx] = gray
                }
            }
            return result
        } else if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                  pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            guard let yPlaneAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let yPtr = yPlaneAddress.assumingMemoryBound(to: UInt8.self)

            for dy in 0..<sampleHeight {
                let sy = cropY + Int(Double(dy) * stepY)
                let rowStart = sy * yBytesPerRow
                for dx in 0..<sampleWidth {
                    let sx = cropX + Int(Double(dx) * stepX)
                    result[dy * sampleWidth + dx] = yPtr[rowStart + sx]
                }
            }
            return result
        }

        return nil
    }
}
