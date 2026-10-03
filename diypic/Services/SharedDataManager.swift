import Foundation
import Combine

public final class SharedDataManager: ObservableObject {

    public static let shared = SharedDataManager()
    public let appGroupID = "group.com.fu5502.diypic"

    @Published public var isAppGroupAvailable: Bool = false
    @Published public var availableSessions: [(session: CaptureSession, dirURL: URL)] = []
    @Published public var latestSession: (session: CaptureSession, dirURL: URL)?
    @Published public var diagnosticMessage: String = ""

    private init() {
        listenForDarwinNotifications()
        reloadSessions()
    }

    public var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    public func reloadSessions() {
        guard let container = containerURL else {
            DispatchQueue.main.async {
                self.isAppGroupAvailable = false
                self.diagnosticMessage = "App Group 共享容器未启用（免费自签名不支持跨进程共享）。建议使用相册截图或录屏合成。"
                self.availableSessions = []
                self.latestSession = nil
            }
            return
        }

        DispatchQueue.main.async {
            self.isAppGroupAvailable = true
        }

        let capturesDir = container.appendingPathComponent("Captures", isDirectory: true)
        guard let subdirs = try? FileManager.default.contentsOfDirectory(
            at: capturesDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            DispatchQueue.main.async {
                self.diagnosticMessage = "已连接共享容器，暂无录屏捕获记录。"
                self.availableSessions = []
                self.latestSession = nil
            }
            return
        }

        var results: [(session: CaptureSession, dirURL: URL)] = []

        for dir in subdirs {
            let sessionJsonURL = dir.appendingPathComponent("session.json")
            if let data = try? Data(contentsOf: sessionJsonURL),
               let session = try? JSONDecoder().decode(CaptureSession.self, from: data) {
                results.append((session, dir))
            }
        }

        results.sort { $0.session.createdAt > $1.session.createdAt }

        DispatchQueue.main.async {
            self.availableSessions = results
            self.latestSession = results.first
            self.diagnosticMessage = "已发现 \(results.count) 条录屏广播记录。"
        }
    }

    public func deleteSession(dirURL: URL) {
        try? FileManager.default.removeItem(at: dirURL)
        reloadSessions()
    }

    private func listenForDarwinNotifications() {
        let notificationName = "com.fu5502.diypic.newCapture" as CFString
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let manager = Unmanaged<SharedDataManager>.fromOpaque(observer).takeUnretainedValue()
                manager.reloadSessions()
            },
            notificationName,
            nil,
            .deliverImmediately
        )
    }
}
