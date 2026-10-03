import SwiftUI
import PhotosUI
import Photos

public struct ContentView: View {

    @StateObject private var sharedManager = SharedDataManager.shared
    @StateObject private var photoManager = PhotoPermissionManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var isProcessing: Bool = false
    @State private var processingStatusText: String = "正在拼装长图..."
    @State private var stitchedImage: UIImage? = nil
    @State private var showResultView: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false

    // AppStorage to record the last automatically stitched session ID
    @AppStorage("lastAutoShownSessionId") private var lastAutoShownSessionId: String = ""

    // Multi-screenshot picker
    @State private var selectedImageItems: [PhotosPickerItem] = []
    @State private var removeOverlapOption: Bool = true

    // Video picker fallback
    @State private var selectedVideoItem: PhotosPickerItem? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Photo Permission Warning Banner (if limited or denied)
                    if photoManager.isLimited || photoManager.isDenied {
                        photoPermissionBanner
                    }

                    // Notification Permission Banner (if not authorized)
                    if !notificationManager.isAuthorized {
                        notificationPermissionBanner
                    }

                    // Main Function 1: Multi-Screenshot Stitching (Top Priority!)
                    multiScreenshotCard

                    // Main Function 2: Video to Long Screenshot
                    videoImportCard

                    // Main Function 3: ReplayKit Broadcast Section
                    broadcastSection

                    // Diagnostics / App Group Status Note
                    if !sharedManager.isAppGroupAvailable {
                        appGroupNoticeCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("diypic 长截屏")
            .refreshable {
                sharedManager.reloadSessions()
                photoManager.checkStatus()
                notificationManager.checkAuthorization()
            }
            .fullScreenCover(isPresented: $showResultView) {
                if let img = stitchedImage {
                    StitchResultView(image: img)
                }
            }
            .alert("提示", isPresented: $showErrorAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "处理失败，请重试")
            }
            .onChange(of: selectedImageItems) { newItems in
                if !newItems.isEmpty {
                    handlePickedImages(items: newItems)
                }
            }
            .onChange(of: selectedVideoItem) { newItem in
                if let item = newItem {
                    handlePickedVideo(item: item)
                }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    handleAppBecameActive()
                }
            }
            .onChange(of: notificationManager.pendingSessionIdToOpen) { pendingId in
                if let id = pendingId {
                    handleOpenFromNotification(sessionId: id)
                }
            }
            .onAppear {
                handleAppBecameActive()
            }
            .overlay {
                if isProcessing && !showResultView {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.3)
                                .tint(.white)
                            Text(processingStatusText)
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(28)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .shadow(radius: 12)
                    }
                }
            }
        }
    }

    // MARK: - 1. Multi-Screenshot Stitching Card (Top Requested Feature!)

    private var multiScreenshotCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue)
                        .frame(width: 44, height: 44)
                    Image(systemName: "photo.stack.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("相册连续截图拼长图")
                        .font(.headline)
                    Text("选择多张连续滚动的截图，自动识别重叠并缝合")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Mode toggle: smart overlap elimination vs direct vertical stack
            HStack {
                Toggle(isOn: $removeOverlapOption) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("智能消除重叠内容")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(removeOverlapOption ? "自动去除相邻截图间的重复部分（无缝长图）" : "保留全部内容按顺序纵向拼接")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .tint(.blue)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color(.tertiarySystemFill))
            .cornerRadius(10)

            PhotosPicker(
                selection: $selectedImageItems,
                maxSelectionCount: 30,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("从相册选取多张截图制作长图")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
        )
    }

    // MARK: - 2. Video Import Card

    private var videoImportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.purple)
                        .frame(width: 44, height: 44)
                    Image(systemName: "video.badge.waveform.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("录屏视频一键转长图")
                        .font(.headline)
                    Text("用系统自带录屏录制一段滑动视频，导入自动转长截图")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            PhotosPicker(
                selection: $selectedVideoItem,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "film")
                    Text("从相册选取滚屏视频合成")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemFill))
                .foregroundColor(.primary)
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - 3. Broadcast Section

    private var broadcastSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("控制中心屏幕广播", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
                if sharedManager.isAppGroupAvailable {
                    Text("已就绪")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                }
            }

            if let latest = sharedManager.latestSession {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("捕获于: \(Date(timeIntervalSince1970: latest.session.createdAt).formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(latest.session.frames.count) 个切片")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    Button {
                        generateLongScreenshot(session: latest.session, dirURL: latest.dirURL)
                    } label: {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text("合成此录屏长图")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemFill))
                .cornerRadius(10)
            }

            // Tutorial
            VStack(alignment: .leading, spacing: 8) {
                Text("操作步骤：")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Text("1. 控制中心长按「屏幕录制」按钮")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("2. 选中「diypic 滚动截屏」并点击开始直播")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("3. 缓慢向下滑动屏幕，点击顶部红点结束录制")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - 4. Notice Card for App Group Limitation on Free Sideloading

    private var appGroupNoticeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("自签名环境说明")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Spacer()
            }

            Text("当前设备通过免费 Apple ID 签名安装，iOS 系统限制了免费自签名的 App Group 跨进程共享权限，因此控制中心广播可能无法传递数据给 App。")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("👉 强烈建议使用上方的【相册连续截图拼长图】或【录屏视频转长图】，不受任何证书与系统限制，100% 稳定生成无缝长图！")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.blue)
        }
        .padding()
        .background(Color.blue.opacity(0.08))
        .cornerRadius(14)
    }

    // MARK: - Permission Banners

    private var photoPermissionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                Text(photoManager.isLimited ? "相册访问受限（仅选定照片）" : "相册权限未开启")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            Text("为确保生成的长截图能直接保存到相册并支持多图导入，建议在设置中开启「全部照片」权限。")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                PhotoPermissionManager.openSystemSettings()
            } label: {
                HStack {
                    Image(systemName: "gearshape.fill")
                    Text("前往设置开启「全部照片」权限")
                }
                .font(.caption)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.15))
                .foregroundColor(.orange)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
    }

    private var notificationPermissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .foregroundColor(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("开启录屏结束通知")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("结束录屏后自动弹出提醒，点击直达长截图")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("允许") {
                Task {
                    _ = await notificationManager.requestAuthorization()
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Handlers

    private func handlePickedImages(items: [PhotosPickerItem]) {
        isProcessing = true
        processingStatusText = "正在读取所选的 \(items.count) 张截图..."

        Task {
            var loadedImages: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    loadedImages.append(img)
                }
            }

            await MainActor.run {
                self.selectedImageItems = [] // Reset selection
                if loadedImages.count < 2 {
                    self.isProcessing = false
                    if let single = loadedImages.first {
                        self.stitchedImage = single
                        self.showResultView = true
                    } else {
                        self.errorMessage = "未能成功读取所选图片，请重试"
                        self.showErrorAlert = true
                    }
                    return
                }

                self.processingStatusText = self.removeOverlapOption ? "正在智能比对重叠区域并缝合..." : "正在顺序拼接多张长图..."
            }

            let result = await StitchEngine.shared.stitchMultipleImages(
                images: loadedImages,
                removeOverlap: self.removeOverlapOption
            )

            await MainActor.run {
                self.isProcessing = false
                if let finalImage = result {
                    self.stitchedImage = finalImage
                    self.showResultView = true
                } else {
                    self.errorMessage = "多张图片拼接失败，请确认图片是否按滑动顺序排列"
                    self.showErrorAlert = true
                }
            }
        }
    }

    private func handleAppBecameActive() {
        sharedManager.reloadSessions()
        photoManager.checkStatus()
        notificationManager.checkAuthorization()

        guard let latest = sharedManager.latestSession else { return }

        let ageInSeconds = Date().timeIntervalSince1970 - latest.session.createdAt
        if ageInSeconds < 1800 && latest.session.id != lastAutoShownSessionId {
            lastAutoShownSessionId = latest.session.id
            generateLongScreenshot(session: latest.session, dirURL: latest.dirURL, isAutoTriggered: true)
        }
    }

    private func handleOpenFromNotification(sessionId: String) {
        sharedManager.reloadSessions()
        notificationManager.pendingSessionIdToOpen = nil

        if let match = sharedManager.availableSessions.first(where: { $0.session.id == sessionId }) {
            generateLongScreenshot(session: match.session, dirURL: match.dirURL, isAutoTriggered: true)
        }
    }

    private func generateLongScreenshot(session: CaptureSession, dirURL: URL, isAutoTriggered: Bool = false) {
        isProcessing = true
        processingStatusText = isAutoTriggered ? "发现新录屏，正在自动合成长图..." : "正在无缝拼装长图..."

        Task {
            if let result = await StitchEngine.shared.stitchSession(session: session, dirURL: dirURL) {
                await MainActor.run {
                    self.stitchedImage = result
                    self.isProcessing = false
                    self.showResultView = true
                }
            } else {
                await MainActor.run {
                    self.isProcessing = false
                    if !isAutoTriggered {
                        self.errorMessage = "图像拼接失败，切片数量过少或未检测到有效滑动"
                        self.showErrorAlert = true
                    }
                }
            }
        }
    }

    private func handlePickedVideo(item: PhotosPickerItem) {
        isProcessing = true
        processingStatusText = "正在解析相册视频并计算位移..."
        item.loadTransferable(type: VideoTransferable.self) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let video):
                    guard let video = video else {
                        self.isProcessing = false
                        return
                    }
                    Task {
                        let img = await StitchEngine.shared.stitchFromVideo(videoURL: video.url) { _ in }
                        await MainActor.run {
                            self.isProcessing = false
                            if let img = img {
                                self.stitchedImage = img
                                self.showResultView = true
                            } else {
                                self.errorMessage = "视频转长图失败，未检测到垂直位移"
                                self.showErrorAlert = true
                            }
                        }
                    }
                case .failure(let err):
                    self.isProcessing = false
                    self.errorMessage = "读取视频失败: \(err.localizedDescription)"
                    self.showErrorAlert = true
                }
            }
        }
    }
}

// Transferable helper for video selection from PhotosPicker
struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let targetURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")
            try FileManager.default.copyItem(at: received.file, to: targetURL)
            return Self(url: targetURL)
        }
    }
}
