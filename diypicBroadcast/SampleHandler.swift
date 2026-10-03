import ReplayKit
import CoreMedia
import CoreVideo
import CoreImage
import UniformTypeIdentifiers
import UserNotifications

public class SampleHandler: RPBroadcastSampleHandler {

    private let appGroupID = "group.com.fu5502.diypic"
    private var sessionURL: URL?
    private var currentSession: CaptureSession?

    private let motionEstimator = MotionEstimator()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    // Rate limiting: throttle to ~12-15 fps to stay well below 50MB memory & low CPU
    private var lastProcessTime: TimeInterval = 0
    private let minFrameInterval: TimeInterval = 0.07 // ~14 fps

    private var frameCounter: Int = 0
    private var accumulatedOffset: CGFloat = 0
    private var isFirstFrame: Bool = true

    public override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        super.broadcastStarted(withSetupInfo: setupInfo)

        motionEstimator.reset()
        frameCounter = 0
        accumulatedOffset = 0
        isFirstFrame = true
        lastProcessTime = 0

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            let error = NSError(
                domain: "com.fu5502.diypic",
                code: -1001,
                userInfo: [NSLocalizedDescriptionKey: "当前自签名未启用 App Group 跨进程权限。请打开 diypic App 使用「相册连续截图拼长图」或「录屏视频转长图」"]
            )
            finishBroadcastWithError(error)
            return
        }

        let sessionId = UUID().uuidString
        let capturesDir = containerURL.appendingPathComponent("Captures", isDirectory: true)
        let thisSessionURL = capturesDir.appendingPathComponent(sessionId, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: thisSessionURL, withIntermediateDirectories: true)
            self.sessionURL = thisSessionURL
            self.currentSession = CaptureSession(
                id: sessionId,
                createdAt: Date().timeIntervalSince1970,
                screenWidth: 0,
                screenHeight: 0,
                topMarginRatio: Double(motionEstimator.topMarginRatio),
                bottomMarginRatio: Double(motionEstimator.bottomMarginRatio),
                frames: []
            )
        } catch {
            print("Failed to initialize capture session directory: \(error)")
        }
    }

    public override func broadcastPaused() {
        super.broadcastPaused()
    }

    public override func broadcastResumed() {
        super.broadcastResumed()
        motionEstimator.reset()
    }

    public override func broadcastFinished() {
        super.broadcastFinished()
        finalizeSession()
    }

    public override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        let now = CACurrentMediaTime()
        guard now - lastProcessTime >= minFrameInterval else { return }
        lastProcessTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let sessionDir = sessionURL else {
            return
        }

        autoreleasepool {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            if isFirstFrame {
                isFirstFrame = false
                currentSession = CaptureSession(
                    id: currentSession?.id ?? UUID().uuidString,
                    createdAt: currentSession?.createdAt ?? Date().timeIntervalSince1970,
                    screenWidth: width,
                    screenHeight: height,
                    topMarginRatio: Double(motionEstimator.topMarginRatio),
                    bottomMarginRatio: Double(motionEstimator.bottomMarginRatio),
                    frames: []
                )

                // Save initial base frame
                let filename = "frame_0000.jpg"
                let fileURL = sessionDir.appendingPathComponent(filename)
                if savePixelBuffer(pixelBuffer, to: fileURL) {
                    currentSession?.frames.append(
                        FrameRecord(filename: filename, offsetY: 0, timestamp: now)
                    )
                    frameCounter += 1
                }
                _ = motionEstimator.estimateOffset(pixelBuffer: pixelBuffer)
                return
            }

            // Estimate scroll displacement
            guard let estimate = motionEstimator.estimateOffset(pixelBuffer: pixelBuffer) else {
                return
            }

            let deltaY = estimate.offsetY
            let confidence = estimate.confidence

            // Only capture if user has actually scrolled down with good confidence
            if deltaY >= motionEstimator.minScrollPixelThreshold && confidence >= 0.35 {
                accumulatedOffset += deltaY

                let filename = String(format: "frame_%04d.jpg", frameCounter)
                let fileURL = sessionDir.appendingPathComponent(filename)

                if savePixelBuffer(pixelBuffer, to: fileURL) {
                    currentSession?.frames.append(
                        FrameRecord(filename: filename, offsetY: deltaY, timestamp: now)
                    )
                    frameCounter += 1
                }
            }
        }
    }

    private func savePixelBuffer(_ pixelBuffer: CVPixelBuffer, to url: URL) -> Bool {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        do {
            try ciContext.writeJPEGRepresentation(
                of: ciImage,
                to: url,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85]
            )
            return true
        } catch {
            print("Failed to save frame: \(error)")
            return false
        }
    }

    private func finalizeSession() {
        guard let session = currentSession,
              let sessionDir = sessionURL,
              !session.frames.isEmpty else {
            let error = NSError(
                domain: "com.fu5502.diypic",
                code: -1002,
                userInfo: [NSLocalizedDescriptionKey: "未检测到有效的屏幕滑动切片。请在录制时平稳向下滑动屏幕。"]
            )
            finishBroadcastWithError(error)
            return
        }

        let sessionFile = sessionDir.appendingPathComponent("session.json")
        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: sessionFile, options: .atomic)

            if let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID
            ) {
                let latestFile = containerURL.appendingPathComponent("latest_session.json")
                try data.write(to: latestFile, options: .atomic)
            }

            // Send local notification to user
            let content = UNMutableNotificationContent()
            content.title = "长截图已生成 ✨"
            content.body = "录屏已结束，点击立即查看、保存并分享长截图"
            content.sound = .default
            content.userInfo = ["sessionId": session.id]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
            let request = UNNotificationRequest(
                identifier: "diypic.capture.\(session.id)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)

            // Post Darwin notification to wake/inform main app
            let notificationName = CFNotificationName("com.fu5502.diypic.newCapture" as CFString)
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                notificationName,
                nil,
                nil,
                true
            )
        } catch {
            print("Failed to save session metadata: \(error)")
        }
    }
}
