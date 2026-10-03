import Foundation
import Photos
import UIKit
import Combine

public final class PhotoPermissionManager: ObservableObject {

    public static let shared = PhotoPermissionManager()

    @Published public var authorizationStatus: PHAuthorizationStatus = .notDetermined

    private init() {
        checkStatus()
    }

    public func checkStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
    }

    /// Requests full readWrite photo library authorization
    public func requestFullAccess() async -> PHAuthorizationStatus {
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = newStatus
        }
        return newStatus
    }

    public var isFullAccess: Bool {
        authorizationStatus == .authorized
    }

    public var isLimited: Bool {
        authorizationStatus == .limited
    }

    public var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Open device Settings app directly to diypic permissions page
    public static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else {
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
