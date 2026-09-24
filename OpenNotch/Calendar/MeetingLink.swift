import SwiftUI
import EventKit

/// A video-call link found on a calendar event. Calendar apps don't agree on
/// where it goes — Google puts Meet in the location, Outlook buries Teams in
/// the notes, Zoom's plugin uses the URL field — so all three are searched.
struct MeetingLink: Equatable {
    let url: URL
    let service: String

    /// How early the Join button appears. Early enough to join a minute or
    /// two before the start; late enough that the strip isn't a wall of
    /// buttons for meetings that are hours away.
    static let joinLead: TimeInterval = 10 * 60

    private static let patterns: [(service: String, regex: NSRegularExpression)] = [
        ("Zoom", #"(?:https?://)?(?:[\w-]+\.)?zoom\.(?:us|com)/(?:j|my|w|s)/[^\s<>"')\]]+"#),
        ("Google Meet", #"(?:https?://)?meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#),
        ("Teams", #"(?:https?://)?teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet)/[^\s<>"')\]]+"#),
        ("Webex", #"(?:https?://)?[\w-]+\.webex\.com/[^\s<>"')\]]+"#),
        ("FaceTime", #"(?:https?://)?facetime\.apple\.com/join[^\s<>"')\]]+"#),
        ("Slack", #"(?:https?://)?app\.slack\.com/huddle/[^\s<>"')\]]+"#),
        ("Chime", #"(?:https?://)?chime\.aws/\d+"#),
        ("GoTo", #"(?:https?://)?(?:meet\.goto\.com|global\.gotomeeting\.com/join)/\d+"#),
        ("Jitsi", #"(?:https?://)?meet\.jit\.si/[^\s<>"')\]]+"#),
        ("Whereby", #"(?:https?://)?whereby\.com/[^\s<>"')\]]+"#),
    ].compactMap { service, pattern in
        (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)).map { (service, $0) }
    }

    /// The first recognised meeting link on the event, checking the URL field
    /// first because it is the one place a link is put on purpose.
    static func find(in event: EKEvent) -> MeetingLink? {
        for text in [event.url?.absoluteString, event.location, event.notes] {
            guard let text, !text.isEmpty else { continue }
            if let link = find(in: text) { return link }
        }
        return nil
    }

    static func find(in text: String) -> MeetingLink? {
        let range = NSRange(text.startIndex..., in: text)
        for (service, regex) in patterns {
            guard let match = regex.firstMatch(in: text, range: range),
                  let swiftRange = Range(match.range, in: text) else { continue }
            // Sentence punctuation that the character class let through.
            var raw = String(text[swiftRange])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            // Locations are often typed without a scheme ("meet.google.com/…").
            if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
            if let url = URL(string: raw) { return MeetingLink(url: url, service: service) }
        }
        return nil
    }

    /// Zoom's https links open a browser tab that then asks to launch Zoom.
    /// When the Zoom app is installed, go straight to it instead.
    func open() {
        if let direct = zoomAppURL,
           NSWorkspace.shared.urlForApplication(toOpen: direct) != nil {
            NSWorkspace.shared.open(direct)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private var zoomAppURL: URL? {
        guard service == "Zoom",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host else { return nil }
        let path = parts.path.split(separator: "/")
        guard path.count >= 2, path[0] == "j" else { return nil }
        var direct = URLComponents()
        direct.scheme = "zoommtg"
        direct.host = host
        direct.path = "/join"
        direct.queryItems = [
            URLQueryItem(name: "action", value: "join"),
            URLQueryItem(name: "confno", value: String(path[1])),
        ] + (parts.queryItems?.filter { $0.name == "pwd" } ?? [])
        return direct.url
    }
}

/// Accent pill that joins the call. Shown only while an event is joinable
/// (see `UpcomingEvent.isJoinable`); further out, rows carry a quiet video
/// glyph instead so it's clear a link exists without asking for a click.
struct JoinMeetingButton: View {
    let link: MeetingLink
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button { link.open() } label: {
            HStack(spacing: 3) {
                Image(systemName: "video.fill").font(Typography.icon(9, .semibold))
                Text("Join").font(Typography.micro(.semibold))
            }
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(settings.accent))
            .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .help("Join on \(link.service)")
        .accessibilityLabel("Join \(link.service) call")
        .fixedSize()
    }
}
