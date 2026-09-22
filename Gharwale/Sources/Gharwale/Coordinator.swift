import AppKit

/// Decides what the family says and when:
/// scheduler → suppression rules → who speaks (escalation) → line → overlay.
@MainActor
final class Coordinator {
    let settings: AppSettings
    let license: LicenseManager
    let content = ContentEngine()
    let overlay = OverlayController()
    let scheduler = Scheduler()
    let calendar = CalendarWatcher()

    /// Called whenever something the menu bar shows has changed.
    var onStateChange: (() -> Void)?

    private(set) var pausedUntil: Date?
    private var active: Active?

    private struct Active {
        let kind: ReminderKind
        let level: Int
        let speaker: FamilyMember
        let isPreview: Bool
    }

    /// Extra {placeholders} for the line being shown, e.g. {meeting} and {minutes}.
    private var replacements: [String: String] = [:]

    /// Stay quiet if there's been no input for this long.
    private let idleThreshold: TimeInterval = 180
    /// How long a bubble waits for an answer before counting as ignored.
    private let answerTimeout: TimeInterval = 25

    init(settings: AppSettings, license: LicenseManager) {
        self.settings = settings
        self.license = license
    }

    func start() {
        scheduler.onTick = { [weak self] now in self?.tick(now) }
        scheduler.start()
    }

    // MARK: - State for the menu bar

    var isPaused: Bool {
        if let p = pausedUntil { return p > Date() }
        return false
    }

    var statusLine: String {
        if isPaused, let p = pausedUntil {
            return "Paused until \(p.formatted(date: .omitted, time: .shortened))"
        }
        let n = todayCount
        return n == 1 ? "1 check-in today" : "\(n) check-ins today"
    }

    func pause(minutes: Int) {
        pausedUntil = Date().addingTimeInterval(Double(minutes * 60))
        scheduler.clearSnoozes()
        overlay.hide()
        onStateChange?()
    }

    func resume() {
        pausedUntil = nil
        onStateChange?()
    }

    // MARK: - Tick

    private func tick(_ now: Date) {
        guard settings.prefs.onboarded, !overlay.isShowing else { return }
        if isPaused { return }
        if pausedUntil != nil { pausedUntil = nil; onStateChange?() }

        // Meetings first: they can't wait.
        let meetingCfg = settings.config(.meeting)
        if meetingCfg.enabled,
           let meeting = calendar.nextMeeting(now: now, leadMinutes: meetingCfg.intervalMinutes) {
            if canShowMeeting() {
                calendar.markAnnounced(meeting)
                present(.meeting, level: 0, now: now, preview: false, meeting: meeting)
                return
            }
        }

        for due in scheduler.dueReminders(now: now, prefs: settings.prefs) where canShow(due.kind, now: now) {
            present(due.kind, level: due.level, now: now, preview: false)
            return
        }
    }

    private func canShow(_ kind: ReminderKind, now: Date) -> Bool {
        let p = settings.prefs
        if !kind.bypassesQuiet {
            if isQuietHour(now, start: p.quietStartHour, end: p.quietEndHour) { return false }
            if todayCount >= p.dailyCap { return false }
        }
        if SystemSensors.idleSeconds > idleThreshold { return false }
        if let front = SystemSensors.frontmostBundleID, p.doNotDisturbBundleIDs.contains(front) { return false }
        if SystemSensors.frontmostIsFullScreen() { return false }
        return true
    }

    /// Meeting heads-ups skip quiet hours, the daily cap and the full-screen rule,
    /// but not if you're away or already on a call.
    private func canShowMeeting() -> Bool {
        if SystemSensors.idleSeconds > idleThreshold { return false }
        if let front = SystemSensors.frontmostBundleID,
           settings.prefs.doNotDisturbBundleIDs.contains(front) { return false }
        return true
    }

    private func isQuietHour(_ date: Date, start: Int, end: Int) -> Bool {
        guard start != end else { return false }
        let h = Calendar.current.component(.hour, from: date)
        return start < end ? (h >= start && h < end) : (h >= start || h < end)
    }

    // MARK: - Presenting

    /// Shows a reminder right now, ignoring the rules. Used by "Try a reminder".
    func preview(_ kind: ReminderKind) {
        active = nil
        var sample: MeetingInfo?
        if kind == .meeting {
            let minutes = settings.config(.meeting).intervalMinutes
            sample = MeetingInfo(key: "preview", title: "Team standup",
                                 start: Date().addingTimeInterval(Double(minutes * 60)), joinURL: nil)
        }
        present(kind, level: 0, now: Date(), preview: true, meeting: sample)
    }

    private func present(_ kind: ReminderKind, level: Int, now: Date, preview: Bool,
                         meeting: MeetingInfo? = nil) {
        if let m = meeting {
            let minutes = max(1, Int((m.start.timeIntervalSince(now) / 60).rounded()))
            replacements = ["{meeting}": m.title, "{minutes}": "\(minutes)"]
        } else {
            replacements = [:]
        }

        let prefs = settings.prefs
        let tone = effectiveTone
        let owner = settings.owner(for: kind)

        // Escalation chain: owner asks, owner asks again, then the other parent steps in.
        var speaker = owner
        var stage: Stage = .ask
        if level >= 2, prefs.escalationEnabled, prefs.family.contains(owner.other) {
            speaker = owner.other
            stage = .escalate
        }

        guard let line = content.pick(character: speaker, reminder: kind, stage: stage, tone: tone)
                ?? content.pick(character: speaker, reminder: kind, stage: .ask, tone: tone)
        else {
            NSLog("Gharwale: no line for \(speaker.rawValue)/\(kind.rawValue)")
            return
        }

        if !preview {
            if !kind.isCalendarBased { scheduler.markShown(kind, at: now) }
            bumpCount()
            onStateChange?()
        }
        active = Active(kind: kind, level: level, speaker: speaker, isPreview: preview)

        let primary = render(character: line.character, mood: line.mood, text: line.text, translation: line.translation)
        var secondary: Utterance?
        if let f = line.followup, prefs.family.contains(f.character) {
            secondary = render(character: f.character, mood: f.mood ?? .neutral, text: f.text, translation: f.translation)
        }

        var buttons = [
            OverlayButton(title: doneTitle(kind, speaker: speaker), isPrimary: true) { [weak self] in
                self?.handleDone()
            },
        ]
        if kind.isCalendarBased {
            if let url = meeting?.joinURL {
                buttons.append(OverlayButton(title: "Join", isPrimary: false) { [weak self] in
                    NSWorkspace.shared.open(url)
                    self?.handleDone()
                })
            }
        } else {
            buttons.append(OverlayButton(title: snoozeTitle(kind), isPrimary: false) { [weak self] in
                self?.handleSnooze()
            })
        }

        overlay.show(primary: primary, secondary: secondary, buttons: buttons,
                     timeout: answerTimeout + (secondary == nil ? 0 : 3)) { [weak self] in
            self?.handleSnooze()
        }
    }

    // MARK: - Answers

    private func handleDone() {
        guard let a = active else { overlay.hide(); return }
        active = nil

        // Sometimes the other parent reacts instead: a small family moment.
        let family = settings.prefs.family
        let reactor: FamilyMember = (family.contains(a.speaker.other) && Int.random(in: 0..<3) == 0)
            ? a.speaker.other : a.speaker

        if let line = content.pick(character: reactor, reminder: a.kind, stage: .done, tone: effectiveTone) {
            overlay.react(render(character: line.character, mood: line.mood,
                                 text: line.text, translation: line.translation),
                          hideAfter: 2.6)
        } else {
            overlay.hide()
        }
    }

    /// Snoozed or ignored: come back later, one step further along the escalation chain.
    private func handleSnooze() {
        guard let a = active else { overlay.hide(); return }
        active = nil
        // Previews and meetings are never snoozed: a meeting won't wait.
        if a.isPreview || a.kind.isCalendarBased { overlay.hide(); return }
        scheduler.snooze(a.kind, level: a.level + 1, minutes: settings.prefs.snoozeMinutes, now: Date())
        overlay.hide()
    }

    // MARK: - Helpers

    private var effectiveTone: Tone {
        let t = settings.prefs.tone
        return (t.requiresPro && !license.isPro) ? .soft : t
    }

    private func render(character: FamilyMember, mood: Mood, text: String, translation: String) -> Utterance {
        let prefs = settings.prefs
        let name = prefs.nickname.trimmingCharacters(in: .whitespaces).isEmpty ? "beta" : prefs.nickname
        let extra = replacements
        func fill(_ s: String) -> String {
            var out = s.replacingOccurrences(of: "{name}", with: name)
            for (key, value) in extra { out = out.replacingOccurrences(of: key, with: value) }
            return out
        }

        switch prefs.language {
        case .hinglish:
            return Utterance(character: character, mood: mood, text: fill(text),
                             subtitle: prefs.showTranslation ? fill(translation) : nil)
        case .english:
            return Utterance(character: character, mood: mood, text: fill(translation), subtitle: nil)
        }
    }

    private func doneTitle(_ kind: ReminderKind, speaker: FamilyMember) -> String {
        let who = speaker.displayName
        switch kind {
        case .goodMorning: return "Good morning \(who)"
        case .bedtime: return "Good night \(who)"
        default: return settings.prefs.language == .hinglish ? "Theek hai \(who)" : "Okay \(who)"
        }
    }

    private func snoozeTitle(_ kind: ReminderKind) -> String {
        let m = settings.prefs.snoozeMinutes
        if kind == .bedtime {
            return settings.prefs.language == .hinglish ? "\(m) min aur" : "\(m) more min"
        }
        return "\(m) min"
    }

    // MARK: - Daily count

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private var todayCount: Int {
        let d = UserDefaults.standard
        return d.string(forKey: "gw.countDay") == Self.dayKey(Date()) ? d.integer(forKey: "gw.count") : 0
    }

    private func bumpCount() {
        let next = todayCount + 1
        UserDefaults.standard.set(Self.dayKey(Date()), forKey: "gw.countDay")
        UserDefaults.standard.set(next, forKey: "gw.count")
    }
}
