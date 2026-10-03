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

                    // Header Status
                    headerCard

                    // Latest / Active Capture Banner
                    if let latest = sharedManager.latestSession {
                        latestSessionCard(session: latest.session, dirURL: latest.dirURL)
                    }

                    // How to Use Guide Card
                    tutorialCard

                    // Video Import Fallback Card
                    videoImportCard

                    // History list
                    if sharedManager.availableSessions.count > 1 {
                        historySection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("diypic 滚动长截屏")
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
            .onChange(of: selectedVideoItem) { newItem in
                if let item = newItem {
                    handlePickedVideo(item: item)
                }
            }
            // Trigger auto-stitch when app becomes active or comes to foreground
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    handleAppBecameActive()
                }
            }
            // Trigger auto-stitch when opened from notification
            .onChange(of: notificationManager.pendingSessionIdToOpen) { pendingId in
                if let id = pendingId {
                    handleOpenFromNotification(sessionId: id)
                }
            }
            .onAppear {
                handleAppBecameActive()
            }
            // Global loading overlay during auto-stitching
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

            Text("为确保生成的长截图能直接保存到相册并支持导入视频，建议开启「全部照片」完整访问权限。")
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

    // MARK: - Main Cards

    private var headerCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 54, height: 54)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 26))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("全自动屏幕广播长截图")
                    .font(.headline)
                Text("在任意 App 内滑动屏幕，录屏自动合成无缝长图")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func latestSessionCard(session: CaptureSession, dirURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("已捕获最新录屏", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.blue)
                Spacer()
                Text(Date(timeIntervalSince1970: session.createdAt).formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("共提取 \(session.frames.count) 个关键滚动切片")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("原始屏幕尺寸: \(session.screenWidth) × \(session.screenHeight)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Button {
                generateLongScreenshot(session: session, dirURL: dirURL)
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 4)
                        Text(processingStatusText)
                    } else {
                        Image(systemName: "wand.and.stars")
                        Text("查看 / 重新合成长图")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isProcessing)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
        )
    }

    private var tutorialCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("使用方法 (Picsew 同款)", systemImage: "questionmark.circle.fill")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                stepRow(number: "1", title: "下拉打开控制中心", desc: "在手机任意界面右上角向下滑动唤出控制中心")
                stepRow(number: "2", title: "长按屏幕录制按钮", desc: "重按/长按带有圆形红点的“屏幕录制”快捷图标")
                stepRow(number: "3", title: "勾选「diypic 滚动截屏」", desc: "在列表中选中 diypic，点击「开始直播」")
                stepRow(number: "4", title: "匀速缓缓向下滑动", desc: "切换到要截取的内容页面，平稳向下滚动屏幕")
                stepRow(number: "5", title: "结束录屏直接看图", desc: "点击顶部红色胶囊结束录屏，点击通知或打开 App 即可直接查看合成好的长图！")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func stepRow(number: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                Text(number)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var videoImportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("备选方案：从相册导入录屏", systemImage: "video.badge.plus")
                    .font(.headline)
                Spacer()
            }

            Text("如果未开启控制中心广播，也可以用系统自带录屏录制一段滚屏视频，导入后自动识别合成。")
                .font(.caption)
                .foregroundColor(.secondary)

            PhotosPicker(
                selection: $selectedVideoItem,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
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

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("历史捕获")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(sharedManager.availableSessions.dropFirst(), id: \.session.id) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("捕获时间: \(Date(timeIntervalSince1970: item.session.createdAt).formatted())")
                            .font(.subheadline)
                        Text("\(item.session.frames.count) 个切片")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("查看") {
                        generateLongScreenshot(session: item.session, dirURL: item.dirURL)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        sharedManager.deleteSession(dirURL: item.dirURL)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Auto Stitching & Handlers

    /// Automatically check if there is an unhandled recent capture session and stitch it immediately
    private func handleAppBecameActive() {
        sharedManager.reloadSessions()
        photoManager.checkStatus()
        notificationManager.checkAuthorization()

        guard let latest = sharedManager.latestSession else { return }

        // Only auto-open if recorded recently (within last 30 minutes) and not previously auto-shown
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
