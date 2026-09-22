import AppKit
import SwiftUI

@main
@MainActor
enum GharwaleMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let license = LicenseManager()
    lazy var coordinator = Coordinator(settings: settings, license: license)
    let windows = WindowManager()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(coordinator: coordinator) { [weak self] in
            self?.openSettings()
        }
        coordinator.start()

        if !settings.prefs.onboarded {
            windows.showOnboarding(settings: settings, calendar: coordinator.calendar) { [weak self] in
                // First hello right after onboarding.
                self?.coordinator.preview(.goodMorning)
            }
        }
    }

    func openSettings() {
        windows.showSettings(settings: settings, license: license, calendar: coordinator.calendar)
    }
}

// MARK: - Menu bar

@MainActor
final class StatusBarController: NSObject {
    private let item: NSStatusItem
    private let coordinator: Coordinator
    private let openSettings: () -> Void

    init(coordinator: Coordinator, openSettings: @escaping () -> Void) {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.coordinator = coordinator
        self.openSettings = openSettings
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "house.fill", accessibilityDescription: "Gharwale")
            button.image?.isTemplate = true
        }
        coordinator.onStateChange = { [weak self] in self?.rebuildMenu() }
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: coordinator.statusLine, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if coordinator.isPaused {
            menu.addItem(makeItem("Resume reminders", #selector(resume)))
        } else {
            menu.addItem(makeItem("Pause for 1 hour", #selector(pauseHour)))
        }

        let tryItem = NSMenuItem(title: "Try a reminder", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for kind in ReminderKind.allCases {
            let mi = makeItem(kind.title, #selector(tryReminder(_:)))
            mi.representedObject = kind.rawValue
            sub.addItem(mi)
        }
        tryItem.submenu = sub
        menu.addItem(tryItem)

        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(showSettings), key: ","))
        let quit = NSMenuItem(title: "Quit Gharwale", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func pauseHour() { coordinator.pause(minutes: 60) }
    @objc private func resume() { coordinator.resume() }
    @objc private func showSettings() { openSettings() }

    @objc private func tryReminder(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = ReminderKind(rawValue: raw) else { return }
        coordinator.preview(kind)
    }
}

// MARK: - Windows

@MainActor
final class WindowManager {
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func showSettings(settings: AppSettings, license: LicenseManager, calendar: CalendarWatcher) {
        if settingsWindow == nil {
            let root = SettingsView()
                .environmentObject(settings)
                .environmentObject(license)
                .environmentObject(calendar)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Gharwale Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 540, height: 680))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding(settings: AppSettings, calendar: CalendarWatcher, onFinish: @escaping () -> Void) {
        let root = OnboardingView { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            onFinish()
        }
        .environmentObject(settings)
        .environmentObject(calendar)

        let w = NSWindow(contentViewController: NSHostingController(rootView: root))
        w.title = "Welcome to Gharwale"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        onboardingWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
