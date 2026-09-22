import Foundation

// MARK: - Family

enum FamilyMember: String, Codable, CaseIterable, Identifiable, Hashable {
    case maa, papa

    var id: String { rawValue }
    var displayName: String { self == .maa ? "Maa" : "Papa" }
    /// The other parent, used for escalation and tag-team reactions.
    var other: FamilyMember { self == .maa ? .papa : .maa }
}

// MARK: - Reminders

enum ReminderKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case goodMorning, breakfast, lunch, dinner, water, move, meeting, bedtime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goodMorning: return "Good morning"
        case .breakfast:   return "Breakfast"
        case .lunch:       return "Lunch"
        case .dinner:      return "Dinner"
        case .water:       return "Water"
        case .move:        return "Get up and move"
        case .meeting:     return "Meeting heads-up"
        case .bedtime:     return "Bedtime"
        }
    }

    /// Triggered by calendar events rather than a clock time or interval.
    /// For meetings, `intervalMinutes` means "minutes before the meeting".
    var isCalendarBased: Bool { self == .meeting }

    /// Interval reminders repeat every N minutes; the rest fire once a day at a set time.
    var isInterval: Bool { self == .water || self == .move }

    /// Good morning and bedtime are allowed through quiet hours and the daily cap.
    var bypassesQuiet: Bool { self == .goodMorning || self == .bedtime }

    var defaultConfig: ReminderConfig {
        switch self {
        case .goodMorning: return ReminderConfig(hour: 8,  minute: 30, owner: .maa)
        case .breakfast:   return ReminderConfig(hour: 9,  minute: 0,  owner: .maa)
        case .lunch:       return ReminderConfig(hour: 13, minute: 30, owner: .maa)
        case .dinner:      return ReminderConfig(hour: 20, minute: 30, owner: .maa)
        case .water:       return ReminderConfig(intervalMinutes: 60, owner: .maa)
        case .move:        return ReminderConfig(intervalMinutes: 90, owner: .papa)
        case .meeting:     return ReminderConfig(intervalMinutes: 5, owner: .maa)
        case .bedtime:     return ReminderConfig(hour: 23, minute: 0,  owner: .papa)
        }
    }
}

struct ReminderConfig: Codable, Hashable {
    var enabled: Bool = true
    var hour: Int = 9
    var minute: Int = 0
    var intervalMinutes: Int = 60
    var owner: FamilyMember = .maa
}

// MARK: - Voice

enum Tone: String, Codable, CaseIterable, Identifiable, Hashable {
    case soft, strict

    var id: String { rawValue }
    var displayName: String { self == .soft ? "Soft" : "Strict" }
    var requiresPro: Bool { self == .strict }
}

enum Language: String, Codable, CaseIterable, Identifiable, Hashable {
    case hinglish, english

    var id: String { rawValue }
    var displayName: String { self == .hinglish ? "Hinglish" : "English" }
}

enum Mood: String, Codable, Hashable {
    case neutral, happy, stern, worried, proud
}

enum Stage: String, Codable, Hashable {
    /// First ask by the reminder's owner.
    case ask
    /// The other parent stepping in after repeated snoozes.
    case escalate
    /// Reaction once the user taps "Theek hai".
    case done
}

// MARK: - Content packs

struct Followup: Codable, Hashable {
    let character: FamilyMember
    let text: String
    let translation: String
    let mood: Mood?
}

struct Line: Codable, Hashable {
    let id: String
    let character: FamilyMember
    /// A ReminderKind raw value, or "any".
    let reminder: String
    /// nil = works for every tone.
    let tone: Tone?
    let stage: Stage
    let mood: Mood
    /// Hinglish line. `{name}` is replaced with the user's nickname.
    let text: String
    /// English line: shown in grey under Hinglish, or alone in English mode.
    let translation: String
    /// Optional tag-team line from a second family member.
    let followup: Followup?
}

struct ContentPack: Codable {
    let name: String
    let version: Int
    let lines: [Line]
}

/// What actually appears on screen, after language and nickname are applied.
struct Utterance: Equatable {
    let character: FamilyMember
    let mood: Mood
    let text: String
    let subtitle: String?
}

// MARK: - Preferences

struct Preferences: Codable, Equatable {
    var onboarded = false
    var nickname = "beta"
    var language: Language = .hinglish
    var tone: Tone = .soft
    var showTranslation = true
    var family: Set<FamilyMember> = [.maa, .papa]
    var reminders: [ReminderKind: ReminderConfig] =
        Dictionary(uniqueKeysWithValues: ReminderKind.allCases.map { ($0, $0.defaultConfig) })
    var quietStartHour = 22
    var quietEndHour = 8
    var dailyCap = 12
    var snoozeMinutes = 5
    var escalationEnabled = true
    var launchAtLogin = false
    /// While one of these apps is in front, the family stays quiet (calls, presentations).
    var doNotDisturbBundleIDs: [String] = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.apple.FaceTime",
        "com.apple.iWork.Keynote",
        "com.microsoft.Powerpoint",
        "com.cisco.webexmeetingsapp",
    ]

    init() {}

    /// Tolerant decoding: a missing or unreadable field falls back to its default,
    /// so adding settings in a later version never wipes a user's preferences.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            if let value = try? c.decodeIfPresent(T.self, forKey: key) { return value }
            return fallback
        }
        onboarded = get(.onboarded, d.onboarded)
        nickname = get(.nickname, d.nickname)
        language = get(.language, d.language)
        tone = get(.tone, d.tone)
        showTranslation = get(.showTranslation, d.showTranslation)
        family = get(.family, d.family)
        if family.isEmpty { family = d.family }
        var r = get(.reminders, d.reminders)
        for k in ReminderKind.allCases where r[k] == nil { r[k] = k.defaultConfig }
        reminders = r
        quietStartHour = get(.quietStartHour, d.quietStartHour)
        quietEndHour = get(.quietEndHour, d.quietEndHour)
        dailyCap = get(.dailyCap, d.dailyCap)
        snoozeMinutes = get(.snoozeMinutes, d.snoozeMinutes)
        escalationEnabled = get(.escalationEnabled, d.escalationEnabled)
        launchAtLogin = get(.launchAtLogin, d.launchAtLogin)
        doNotDisturbBundleIDs = get(.doNotDisturbBundleIDs, d.doNotDisturbBundleIDs)
    }
}

// MARK: - Paths

enum AppPaths {
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Gharwale", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Drop extra *.json content packs here to add lines without rebuilding the app.
    static var packsDir: URL {
        let dir = supportDir.appendingPathComponent("Packs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
