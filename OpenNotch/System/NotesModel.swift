import AppKit
import Combine

/// The Notes module: one scratchpad in the panel, kept between launches.
///
/// Off by default, and inert while off: nothing is read from disk until the
/// module is switched on, and switching it off drops the text from memory.
/// The file stays, so turning Notes back on finds them again; the trash button
/// is what deletes them. See `NoteFile` for what is written and where.
final class NotesModel: ObservableObject {
    @Published var text = "" {
        didSet {
            let clamped = NoteFile.clamp(text)
            if clamped != text { text = clamped }
        }
    }

    private let file = NoteFile.standard
    private var running = false
    /// What is on disk, so a load or an unchanged flush writes nothing.
    private var saved = ""
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Typing saves itself once the keys go quiet; quitting or closing the
        // panel saves at once, so nothing waits on the debounce.
        $text
            .dropFirst()
            .debounce(for: .milliseconds(700), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.flush() }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.flush() }
            .store(in: &cancellables)
    }

    func start() {
        guard !running else { return }
        running = true
        saved = file?.load() ?? ""
        text = saved
    }

    func stop() {
        guard running else { return }
        flush()
        running = false
        saved = ""
        text = ""
    }

    func flush() {
        guard running, text != saved, let file else { return }
        do {
            try file.save(text)
            saved = text
        } catch {
            NSLog("AloeNotch: couldn't save notes: \(error.localizedDescription)")
        }
    }

    /// Empties the note and removes the file.
    func clear() {
        text = ""
        flush()
    }
}
