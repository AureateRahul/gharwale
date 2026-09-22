import EventKit
import SwiftUI

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var calendar: CalendarWatcher

    @State private var keyInput = ""
    @State private var licenseMessage: String?
    @State private var activating = false

    var body: some View {
        Form {
            Section("You") {
                TextField("What should they call you?", text: $settings.prefs.nickname)
            }

            Section("Who's at home") {
                ForEach(FamilyMember.allCases) { member in
                    Toggle(member.displayName, isOn: memberBinding(member))
                }
                Text("Dadi, Didi, Bhaiya and the rest of the family are moving in with Pro updates.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Voice") {
                Picker("Language", selection: $settings.prefs.language) {
                    ForEach(Language.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Tone", selection: toneBinding) {
                    ForEach(Tone.allCases) { tone in Text(toneLabel(tone)).tag(tone) }
                }
                Toggle("Show the English line underneath", isOn: $settings.prefs.showTranslation)
                    .disabled(settings.prefs.language == .english)
            }

            Section("Reminders") {
                ForEach(ReminderKind.allCases) { kind in
                    ReminderRow(kind: kind, config: reminderBinding(kind))
                }
            }

            Section("Calendar") {
                CalendarConnectRow()
                Text("Maa and Papa read the calendars in the Calendar app on this Mac: iCloud, Google, Outlook and anything else added in System Settings → Internet Accounts. They only read event titles, times and meeting links, and nothing leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Keeping it calm") {
                Picker("Quiet hours start", selection: $settings.prefs.quietStartHour) {
                    ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                Picker("Quiet hours end", selection: $settings.prefs.quietEndHour) {
                    ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                Stepper("Daily limit: \(settings.prefs.dailyCap) check-ins",
                        value: $settings.prefs.dailyCap, in: 1...40)
                Stepper("Snooze length: \(settings.prefs.snoozeMinutes) min",
                        value: $settings.prefs.snoozeMinutes, in: 1...30)
                Toggle("After two snoozes, the other parent steps in", isOn: $settings.prefs.escalationEnabled)
                Toggle("Launch at login", isOn: launchBinding)
                Text("Good morning and bedtime still come through quiet hours. Nobody appears while you're away, in a full-screen app, or on a call.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Gharwale Pro") {
                if license.isPro {
                    LabeledContent("Status", value: "Active")
                    Button("Deactivate on this Mac") { license.deactivate() }
                } else {
                    Text("Pro unlocks Strict tone now, and the rest of the family as they move in.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        TextField("License key", text: $keyInput)
                        Button(activating ? "Activating…" : "Activate") { activate() }
                            .disabled(keyInput.isEmpty || activating)
                    }
                }
                if let m = licenseMessage {
                    Text(m).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 600)
    }

    // MARK: Bindings

    private func memberBinding(_ m: FamilyMember) -> Binding<Bool> {
        Binding(
            get: { settings.prefs.family.contains(m) },
            set: { on in
                var f = settings.prefs.family
                if on { f.insert(m) } else if f.count > 1 { f.remove(m) }
                settings.prefs.family = f
            })
    }

    private var toneBinding: Binding<Tone> {
        Binding(
            get: { settings.prefs.tone },
            set: { t in
                if t.requiresPro && !license.isPro {
                    licenseMessage = "\(t.displayName) tone is part of Pro."
                } else {
                    settings.prefs.tone = t
                }
            })
    }

    private func reminderBinding(_ k: ReminderKind) -> Binding<ReminderConfig> {
        Binding(get: { settings.config(k) }, set: { settings.prefs.reminders[k] = $0 })
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { settings.prefs.launchAtLogin },
            set: { on in
                settings.prefs.launchAtLogin = on
                settings.setLaunchAtLogin(on)
            })
    }

    private func toneLabel(_ t: Tone) -> String {
        t.requiresPro && !license.isPro ? "\(t.displayName) (Pro)" : t.displayName
    }

    private func hourLabel(_ h: Int) -> String {
        let date = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    @MainActor
    private func activate() {
        activating = true
        licenseMessage = nil
        let key = keyInput
        Task {
            do {
                try await license.activate(key)
                licenseMessage = "Pro is active. Strict Papa says thank you."
                keyInput = ""
            } catch {
                licenseMessage = error.localizedDescription
            }
            activating = false
        }
    }
}

struct ReminderRow: View {
    let kind: ReminderKind
    @Binding var config: ReminderConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(kind.title, isOn: $config.enabled)
            if config.enabled {
                HStack {
                    if kind.isCalendarBased {
                        Stepper("\(config.intervalMinutes) min before",
                                value: $config.intervalMinutes, in: 1...30)
                    } else if kind.isInterval {
                        Stepper("Every \(config.intervalMinutes) min",
                                value: $config.intervalMinutes, in: 15...240, step: 15)
                    } else {
                        DatePicker("At", selection: timeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Spacer()
                    Picker("Asked by", selection: $config.owner) {
                        ForEach(FamilyMember.allCases) { Text($0.displayName).tag($0) }
                    }
                    .frame(width: 170)
                }
                .padding(.leading, 20)
                .font(.callout)
            }
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: config.hour, minute: config.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                config.hour = c.hour ?? config.hour
                config.minute = c.minute ?? config.minute
            })
    }
}

/// Connect button / status for calendar access, used in Settings and onboarding.
struct CalendarConnectRow: View {
    @EnvironmentObject var calendar: CalendarWatcher

    var body: some View {
        HStack {
            switch calendar.status {
            case .authorized:
                Label("Calendar connected", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .notDetermined:
                Text("Get a heads-up before meetings")
                Spacer()
                Button("Connect Calendar") { Task { await calendar.connect() } }
            default:
                Text("Calendar access is off")
                Spacer()
                Button("Open Privacy Settings") { calendar.openPrivacySettings() }
            }
        }
        .onAppear { calendar.refreshStatus() }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var step = 0
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                CharacterFace(member: .maa, mood: step == 2 ? .proud : .happy)
                    .frame(width: 96, height: 96)
                CharacterFace(member: .papa, mood: step == 1 ? .stern : .neutral)
                    .frame(width: 96, height: 96)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black))
            .frame(maxWidth: .infinity)

            Group {
                switch step {
                case 0: family
                case 1: voice
                default: rhythm
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                Text("Step \(step + 1) of 3").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(step == 2 ? "Bring them home" : "Next") {
                    if step < 2 {
                        step += 1
                    } else {
                        settings.prefs.onboarded = true
                        onFinish()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480, height: 520)
    }

    private var family: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meet your family").font(.title2.bold())
            Text("They'll pop out of your notch to make sure you eat, drink water, move and sleep.")
                .foregroundStyle(.secondary)
            TextField("What do they call you? (beta, Munna, Chinku…)", text: $settings.prefs.nickname)
                .textFieldStyle(.roundedBorder)
            ForEach(FamilyMember.allCases) { m in
                Toggle(m.displayName, isOn: Binding(
                    get: { settings.prefs.family.contains(m) },
                    set: { on in
                        var f = settings.prefs.family
                        if on { f.insert(m) } else if f.count > 1 { f.remove(m) }
                        settings.prefs.family = f
                    }))
            }
        }
    }

    private var voice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How do they talk?").font(.title2.bold())
            Picker("Language", selection: $settings.prefs.language) {
                ForEach(Language.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Show the English line underneath", isOn: $settings.prefs.showTranslation)
                .disabled(settings.prefs.language == .english)
            Text("Soft tone is included. Strict tone comes with Pro — you can switch any time in Settings.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var rhythm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick your check-ins").font(.title2.bold())
            ForEach(ReminderKind.allCases) { kind in
                Toggle(isOn: Binding(
                    get: { settings.config(kind).enabled },
                    set: { settings.prefs.reminders[kind]?.enabled = $0 })) {
                    HStack {
                        Text(kind.title)
                        Spacer()
                        Text(summary(kind)).foregroundStyle(.secondary).font(.callout)
                    }
                }
            }
            if settings.config(.meeting).enabled {
                CalendarConnectRow().padding(.top, 4)
            }
            Text("You can change times and who asks in Settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func summary(_ kind: ReminderKind) -> String {
        let c = settings.config(kind)
        if kind.isCalendarBased { return "\(c.intervalMinutes) min before meetings" }
        if kind.isInterval { return "every \(c.intervalMinutes) min" }
        let d = Calendar.current.date(bySettingHour: c.hour, minute: c.minute, second: 0, of: Date()) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }
}
