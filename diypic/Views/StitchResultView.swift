import SwiftUI
import Photos

public struct StitchResultView: View {

    public let image: UIImage
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving: Bool = false
    @State private var showSavedAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showShareSheet: Bool = false

    public init(image: UIImage) {
        self.image = image
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Interactive Scroll / Zoom Image Container
                ZoomableScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
                .background(Color(.systemGroupedBackground))

                // Bottom Action Bar
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("长图分辨率: \(Int(image.size.width)) × \(Int(image.size.height))")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Text("长宽比: 1 : \(String(format: "%.1f", image.size.height / max(1, image.size.width)))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    HStack(spacing: 16) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemFill))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                        }

                        Button {
                            saveImage()
                        } label: {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Label("保存到相册", systemImage: "arrow.down.to.line")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isSaving)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .padding(.top, 12)
                .background(Color(.systemBackground))
            }
            .navigationTitle("长截图预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .alert("提示", isPresented: $showSavedAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showShareSheet) {
                ShareActivityView(activityItems: [image])
            }
        }
    }

    private func saveImage() {
        isSaving = true
        Task {
            do {
                try await StitchEngine.shared.saveToPhotos(image: image)
                await MainActor.run {
                    isSaving = false
                    alertMessage = "成功保存到系统相册！"
                    showSavedAlert = true
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    alertMessage = "保存失败: \(error.localizedDescription)"
                    showSavedAlert = true
                }
            }
        }
    }
}

// UIKit wrapper for smooth pinch-to-zoom and pan
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4.0
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = true

        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        scrollView.addSubview(hostedView)

        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            hostedView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: content))
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>

        init(hostingController: UIHostingController<Content>) {
            self.hostingController = hostingController
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController.view
        }
    }
}

struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
