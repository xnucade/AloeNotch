import SwiftUI

/// The Notes pane: one scratchpad, saved as you type.
///
/// The field only takes focus when clicked, never on appear: opening the panel
/// to glance at the music shouldn't swallow the next thing you type.
struct NotesView: View {
    @ObservedObject var notes: NotesModel
    /// Hidden when the tabbed column supplies its own header.
    var showsHeader = true

    @ObservedObject private var settings = AppSettings.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.snug) {
            if showsHeader {
                HStack(spacing: Metrics.Spacing.snug) {
                    Text("Notes")
                        .font(Typography.micro(.semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Ink.tertiary)
                    Spacer()
                    if !notes.text.isEmpty { NotesClearButton(notes: notes) }
                }
                .frame(height: 16)
            }

            ZStack(alignment: .topLeading) {
                if notes.text.isEmpty {
                    Text("Jot something down")
                        .font(Typography.caption())
                        .foregroundStyle(Ink.quaternary)
                        // Lines up with the editor's own text inset.
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notes.text)
                    .font(Typography.caption())
                    .foregroundStyle(Ink.primary)
                    .tint(settings.accent)
                    .textEditorStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($focused)
                    .onExitCommand { focused = false }
                    .accessibilityLabel("Notes")
            }
            .padding(.horizontal, Metrics.Spacing.tight)
            .padding(.vertical, Metrics.Spacing.tight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Ink.fill)
            }
        }
        // Closing the panel saves at once rather than on the debounce.
        .onDisappear { notes.flush() }
    }
}

/// Deletes the note, file included. Shared by the pane's own header and the
/// tabbed column's.
struct NotesClearButton: View {
    @ObservedObject var notes: NotesModel

    var body: some View {
        Button { withAnimation(Motion.contentFade) { notes.clear() } } label: {
            Image(systemName: "trash")
                .font(Typography.icon(11, .medium))
                .foregroundStyle(.white)
                .hoverLift(restOpacity: 0.5)
        }
        .buttonStyle(PressableButtonStyle())
        .help("Delete this note")
        .accessibilityLabel("Delete note")
    }
}
