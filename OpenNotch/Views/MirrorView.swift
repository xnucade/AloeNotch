import SwiftUI
import AVFoundation

/// The Mirror pane: the camera, mirrored the way a mirror is, in a rounded
/// frame. Appearing is what turns the camera on and disappearing is what turns
/// it off, so it can never run behind a closed panel or another tab.
struct MirrorView: View {
    @ObservedObject var camera: MirrorCamera
    /// Hidden when the tabbed column supplies its own header.
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.snug) {
            if showsHeader {
                Text("Mirror")
                    .font(Typography.micro(.semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.tertiary)
                    .frame(height: 16)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black)
                CameraPreview(session: camera.session)
                    .opacity(camera.status == .live ? 1 : 0)
                overlay
            }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Ink.edge, lineWidth: 1)
            }
            .animation(Motion.contentFade, value: camera.status)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { camera.attach() }
        .onDisappear { camera.detach() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mirror")
    }

    @ViewBuilder
    private var overlay: some View {
        switch camera.status {
        case .denied:
            message("Camera access is off", symbol: "video.slash") {
                Button("Open Settings") {
                    PermissionRequester.openPrivacySettings("Privacy_Camera")
                }
                .buttonStyle(PressableButtonStyle())
                .font(Typography.micro(.semibold))
                .foregroundStyle(Ink.secondary)
            }
        case .noCamera:
            message("No camera found", symbol: "video.slash") { EmptyView() }
        case .off, .starting:
            Image(systemName: "web.camera")
                .font(Typography.icon(18, .light))
                .foregroundStyle(Ink.quaternary)
        case .live:
            EmptyView()
        }
    }

    private func message<Action: View>(_ text: LocalizedStringKey, symbol: String,
                                       @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: Metrics.Spacing.tight) {
            Image(systemName: symbol)
                .font(Typography.icon(15, .light))
                .foregroundStyle(Ink.quaternary)
            Text(text)
                .font(Typography.caption())
                .foregroundStyle(Ink.tertiary)
                .multilineTextAlignment(.center)
            action()
        }
        .padding(Metrics.Spacing.snug)
    }
}

/// An AVCaptureVideoPreviewLayer in a view. Filled to the frame and mirrored,
/// because a camera that moves the wrong way when you lean is a camera, not a
/// mirror.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.mirror()
    }

    final class PreviewView: NSView {
        let preview = AVCaptureVideoPreviewLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layout() {
            super.layout()
            preview.frame = bounds
            mirror()
        }

        /// The connection only exists once the session has its camera, so
        /// this runs again on every layout until it sticks.
        func mirror() {
            guard let c = preview.connection, c.isVideoMirroringSupported, !c.isVideoMirrored else { return }
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }

        // The panel's own hover and click handling stays in charge.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
