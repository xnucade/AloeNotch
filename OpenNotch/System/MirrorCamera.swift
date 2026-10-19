import AVFoundation
import Combine

/// The Mirror module's camera: a live look at yourself before a call.
///
/// The camera runs only while a Mirror pane is on screen, counted across every
/// display's panel, and stops the moment the last one goes. Frames go straight
/// from the capture session to the preview layer; nothing is recorded, kept
/// or sent. macOS shows its camera light the whole time it runs, as it should.
///
/// Access is asked for the first time the pane opens, not when the module is
/// switched on: the prompt should arrive when the camera is about to be used.
final class MirrorCamera: ObservableObject {
    enum Status: Equatable { case off, starting, live, denied, noCamera }

    @Published private(set) var status: Status = .off

    let session = AVCaptureSession()
    /// `startRunning` blocks for a noticeable moment, so the session lives on
    /// its own queue and never on the main thread.
    private let queue = DispatchQueue(label: "com.kadeslab.AloeNotch.mirror")
    /// Touched on `queue` only.
    private var configured = false
    private var viewers = 0

    func attach() {
        viewers += 1
        if viewers == 1 { begin() }
    }

    func detach() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        if status == .live || status == .starting { status = .off }
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func begin() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            status = .starting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !granted { self.status = .denied }
                    else if self.viewers > 0 { self.run() }
                    else { self.status = .off }
                }
            }
        default:
            status = .denied
        }
    }

    private func run() {
        status = .starting
        queue.async { [weak self] in
            guard let self else { return }
            guard self.configured || self.configure() else {
                DispatchQueue.main.async { self.status = .noCamera }
                return
            }
            self.session.startRunning()
            DispatchQueue.main.async {
                // The pane may have closed while the camera spun up.
                if self.viewers > 0 {
                    self.status = .live
                } else {
                    self.queue.async { self.session.stopRunning() }
                }
            }
        }
    }

    /// The built-in camera first, so an iPhone nearby doesn't take over the
    /// mirror through Continuity Camera; any camera after that.
    private func configure() -> Bool {
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // A preview a couple of hundred points wide needs nothing more, and a
        // smaller capture is less work for the camera pipeline.
        if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        configured = true
        return true
    }
}
