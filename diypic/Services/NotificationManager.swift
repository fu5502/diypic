import Foundation
import UserNotifications
import Combine
import UIKit

public final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    public static let shared = NotificationManager()

    @Published public var isAuthorized: Bool = false
    @Published public var pendingSessionIdToOpen: String? = nil

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorization()
    }

    public func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
    }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await MainActor.run {
                self.isAuthorized = granted
            }
            return granted
        } catch {
            print("Failed to request notification permission: \(error)")
            return false
        }
    }

    /// Post a local notification when recording finishes
    public func scheduleCaptureReadyNotification(sessionId: String) {
        let content = UNMutableNotificationContent()
        content.title = "长截图已生成 ✨"
        content.body = "屏幕录制已结束，点击立即查看、保存并分享长截图"
        content.sound = .default
        content.userInfo = ["sessionId": sessionId]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "diypic.capture.\(sessionId)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Deliver notification even when app is in foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle user tapping the notification
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let sessionId = userInfo["sessionId"] as? String {
            DispatchQueue.main.async {
                self.pendingSessionIdToOpen = sessionId
            }
        }
        completionHandler()
    }
}
