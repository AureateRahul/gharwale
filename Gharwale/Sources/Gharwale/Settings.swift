import Foundation
import ServiceManagement

/// Holds the user's preferences and saves them to UserDefaults on every change.
@MainActor
final class AppSettings: ObservableObject {
    @Published var prefs: Preferences {
        didSet { if prefs != oldValue { save() } }
    }

    private let storageKey = "gw.preferences"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Preferences.self, from: data) {
            prefs = saved
        } else {
            prefs = Preferences()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func config(_ kind: ReminderKind) -> ReminderConfig {
        prefs.reminders[kind] ?? kind.defaultConfig
    }

    /// The family member who asks for this reminder. If the configured owner
    /// isn't "at home", the other parent takes over.
    func owner(for kind: ReminderKind) -> FamilyMember {
        let o = config(kind).owner
        if prefs.family.contains(o) { return o }
        return prefs.family.first ?? .maa
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Gharwale: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}

/// One-time Pro purchase, verified by license key.
///
/// MVP behaviour: if `activationEndpoint` is nil (development), any key shaped like
/// GHAR-XXXX-XXXX-XXXX is accepted locally. Before selling Pro, set the endpoint to
/// your payment provider's license-activation URL (Dodo Payments, Lemon Squeezy or
/// Gumroad) and adjust the request body to match their API docs.
@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var isPro: Bool
    @Published private(set) var storedKey: String?

    static let activationEndpoint: URL? = nil

    private let storageKey = "gw.licenseKey"

    enum ActivationError: LocalizedError {
        case invalidFormat
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "That key doesn't look right. It should look like GHAR-XXXX-XXXX-XXXX."
            case .rejected(let why): return "The key was not accepted. \(why)"
            }
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "gw.licenseKey")
        storedKey = saved
        isPro = saved != nil
    }

    func activate(_ raw: String) async throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let endpoint = Self.activationEndpoint {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: String] = [
                "license_key": trimmed,
                "name": Host.current().localizedName ?? "Mac",
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ActivationError.rejected(String(data: data, encoding: .utf8) ?? "")
            }
            store(trimmed)
        } else {
            let key = trimmed.uppercased()
            guard key.range(of: #"^GHAR(-[A-Z0-9]{4}){3}$"#, options: .regularExpression) != nil else {
                throw ActivationError.invalidFormat
            }
            store(key)
        }
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        storedKey = nil
        isPro = false
    }

    private func store(_ key: String) {
        UserDefaults.standard.set(key, forKey: storageKey)
        storedKey = key
        isPro = true
    }
}
