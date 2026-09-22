import AppKit
import EventKit

/// An upcoming meeting the family should mention.
struct MeetingInfo: Equatable {
    /// Identifies this occurrence, so each meeting is announced only once.
    let key: String
    let title: String
    let start: Date
    /// Zoom / Meet / Teams / Webex link found in the invite, if any.
    let joinURL: URL?
}

/// Reads the calendars in the macOS Calendar app (iCloud, Google, Outlook,
/// Exchange — whatever is added in System Settings → Internet Accounts).
/// Read-only: Gharwale never creates or changes events.
@MainActor
final class CalendarWatcher: ObservableObject {
    @Published private(set) var status: EKAuthorizationStatus

    private var store = EKEventStore()
    private var announced: Set<String> = []

    private static let meetingHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "around.co", "gotomeeting.com",
    ]

    init() {
        status = EKEventStore.authorizationStatus(for: .event)
    }

    var isConnected: Bool { status == .authorized }

    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .event)
    }

    /// Shows the macOS permission prompt. Returns true if access was granted.
    @discardableResult
    func connect() async -> Bool {
        let granted: Bool = await withCheckedContinuation { continuation in
            store.requestAccess(to: .event) { ok, _ in continuation.resume(returning: ok) }
        }
        // A fresh store picks up the new permission immediately.
        store = EKEventStore()
        refreshStatus()
        return granted
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The next meeting starting within `leadMinutes` that hasn't been announced yet.
    /// Skips all-day events, cancelled events and invites you declined.
    func nextMeeting(now: Date, leadMinutes: Int) -> MeetingInfo? {
        guard isConnected else { return nil }
        let lead = TimeInterval(max(leadMinutes, 1) * 60)
        let predicate = store.predicateForEvents(withStart: now,
                                                 end: now.addingTimeInterval(lead + 60),
                                                 calendars: nil)
        let events = store.events(matching: predicate)
            .filter { event in
                !event.isAllDay
                    && event.status != .canceled
                    && event.startDate > now
                    && event.startDate.timeIntervalSince(now) <= lead
                    && !Self.youDeclined(event)
            }
            .sorted { $0.startDate < $1.startDate }

        for event in events {
            let key = "\(event.eventIdentifier ?? event.title ?? "event")|\(Int(event.startDate.timeIntervalSince1970))"
            if announced.contains(key) { continue }
            return MeetingInfo(key: key,
                               title: Self.cleanTitle(event.title),
                               start: event.startDate,
                               joinURL: Self.joinURL(for: event))
        }
        return nil
    }

    func markAnnounced(_ meeting: MeetingInfo) {
        if announced.count > 500 { announced.removeAll() }
        announced.insert(meeting.key)
    }

    // MARK: - Helpers

    private static func youDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
    }

    private static func cleanTitle(_ raw: String?) -> String {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "meeting" }
        return t.count > 40 ? String(t.prefix(38)) + "…" : t
    }

    private static func joinURL(for event: EKEvent) -> URL? {
        var candidates: [URL] = []
        if let u = event.url { candidates.append(u) }

        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        if !text.isEmpty,
           let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let u = match.url { candidates.append(u) }
            }
        }

        return candidates.first { url in
            let host = url.host?.lowercased() ?? ""
            return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }
}
