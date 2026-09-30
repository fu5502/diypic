import Foundation
import CoreGraphics

public struct FrameRecord: Codable {
    public let filename: String
    public let offsetY: CGFloat
    public let timestamp: Double

    public init(filename: String, offsetY: CGFloat, timestamp: Double) {
        self.filename = filename
        self.offsetY = offsetY
        self.timestamp = timestamp
    }
}

public struct CaptureSession: Codable, Identifiable {
    public let id: String
    public let createdAt: Double
    public let screenWidth: Int
    public let screenHeight: Int
    public let topMarginRatio: Double
    public let bottomMarginRatio: Double
    public var frames: [FrameRecord]

    public init(
        id: String,
        createdAt: Double,
        screenWidth: Int,
        screenHeight: Int,
        topMarginRatio: Double,
        bottomMarginRatio: Double,
        frames: [FrameRecord]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.topMarginRatio = topMarginRatio
        self.bottomMarginRatio = bottomMarginRatio
        self.frames = frames
    }
}
