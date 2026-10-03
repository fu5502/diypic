import SwiftUI
import UserNotifications

@main
struct DiyPicApp: App {

    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var photoManager = PhotoPermissionManager.shared

    init() {
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // 启动时请求通知权限（便于在录屏结束后弹出横幅通知）
                    _ = await notificationManager.requestAuthorization()

                    // 启动时主动请求相册完整权限（避免只有受限/私密访问）
                    if photoManager.authorizationStatus == .notDetermined {
                        _ = await photoManager.requestFullAccess()
                    } else {
                        photoManager.checkStatus()
                    }
                }
                .onOpenURL { url in
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       let queryItems = components.queryItems,
                       let id = queryItems.first(where: { $0.name == "id" })?.value {
                        notificationManager.pendingSessionIdToOpen = id
                    }
                }
        }
    }
}
