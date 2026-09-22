import AppKit
import CoreGraphics

/// Decides which reminders are due. It never builds a backlog: a fixed-time
/// reminder that couldn't be shown within its grace window is simply skipped.
@MainActor
final class Scheduler {
    struct Due {
        let kind: ReminderKind
        /// How many times this reminder has been snoozed or ignored in a row.
        let level: Int
    }

    private struct Snooze {
        let due: Date
        let level: Int
    }

    var onTick: ((Date) -> Void)?

    private var loop: Task<Void, Never>?
    private var snoozes: [ReminderKind: Snooze] = [:]
    private var lastShown: [String: Double]
    private let launchedAt = Date()
    private let lastShownKey = "gw.lastShown"

    /// How late a fixed-time reminder may still appear (e.g. after waking the Mac).
    static let graceWindow: TimeInterval = 45 * 60
    /// Stop after this many snoozes; nobody wants a fifth lunch reminder.
    static let maxLevel = 3

    init() {
        lastShown = UserDefaults.standard.dictionary(forKey: lastShownKey) as? [String: Double] ?? [:]
    }

    func start() {
        loop?.cancel()
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.onTick?(Date())
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    func dueReminders(now: Date, prefs: Preferences) -> [Due] {
        var result: [Due] = []

        // Snoozed reminders come back first.
        for kind in ReminderKind.allCases {
            if let s = snoozes[kind], now >= s.due { result.append(Due(kind: kind, level: s.level)) }
        }

        for kind in ReminderKind.allCases {
            guard !kind.isCalendarBased, snoozes[kind] == nil,
                  let cfg = prefs.reminders[kind], cfg.enabled else { continue }

            if kind.isInterval {
                let last = lastShown[kind.rawValue].map(Date.init(timeIntervalSince1970:)) ?? .distantPast
                let base = max(last, launchedAt)
                if now.timeIntervalSince(base) >= Double(max(cfg.intervalMinutes, 5) * 60) {
                    result.append(Due(kind: kind, level: 0))
                }
            } else {
                guard let scheduled = Calendar.current.date(
                    bySettingHour: cfg.hour, minute: cfg.minute, second: 0, of: now) else { continue }
                let last = lastShown[kind.rawValue].map(Date.init(timeIntervalSince1970:)) ?? .distantPast
                if now >= scheduled,
                   now.timeIntervalSince(scheduled) < Self.graceWindow,
                   last < scheduled {
                    result.append(Due(kind: kind, level: 0))
                }
            }
        }
        return result
    }

    func markShown(_ kind: ReminderKind, at now: Date) {
        lastShown[kind.rawValue] = now.timeIntervalSince1970
        snoozes[kind] = nil
        UserDefaults.standard.set(lastShown, forKey: lastShownKey)
    }

    /// Brings the reminder back later at a higher escalation level, or drops it.
    func snooze(_ kind: ReminderKind, level: Int, minutes: Int, now: Date) {
        guard level <= Self.maxLevel else {
            snoozes[kind] = nil
            return
        }
        snoozes[kind] = Snooze(due: now.addingTimeInterval(Double(minutes * 60)), level: level)
    }

    func clearSnoozes() { snoozes.removeAll() }
}

/// Reads what the Mac is doing, so the family knows when to stay quiet.
enum SystemSensors {
    /// Seconds since the last keyboard, mouse or trackpad input.
    static var idleSeconds: TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    static var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// True when the frontmost app has a window covering a whole screen
    /// (full-screen video, games, presentations). Reads window bounds only,
    /// which needs no screen-recording permission.
    static func frontmostIsFullScreen() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return false }

        for window in info {
            guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            for screen in NSScreen.screens {
                let usableHeight = screen.frame.height - screen.safeAreaInsets.top
                if abs(bounds.width - screen.frame.width) < 1, bounds.height >= usableHeight - 1 {
                    return true
                }
            }
        }
        return false
    }
}
