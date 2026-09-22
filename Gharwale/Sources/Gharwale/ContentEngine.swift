import Foundation

/// Loads content packs and picks lines: character × reminder × tone × stage,
/// avoiding anything shown recently.
@MainActor
final class ContentEngine {
    private(set) var lines: [Line] = []
    private var recentIDs: [String] = []
    private let recentLimit = 40

    init() { reload() }

    func reload() {
        var all: [Line] = []
        for url in packURLs() {
            do {
                let data = try Data(contentsOf: url)
                let pack = try JSONDecoder().decode(ContentPack.self, from: data)
                all += pack.lines
            } catch {
                NSLog("Gharwale: could not load pack \(url.lastPathComponent): \(error)")
            }
        }
        lines = all
        NSLog("Gharwale: loaded \(all.count) lines")
    }

    /// Bundled core pack, then any user packs in Application Support.
    private func packURLs() -> [URL] {
        var urls: [URL] = []
        if let bundled = Bundle.main.url(forResource: "core", withExtension: "json") {
            urls.append(bundled)
        } else {
            // `swift run` from the repo root: use the pack in the source tree.
            let dev = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("ContentPacks/core.json")
            if FileManager.default.fileExists(atPath: dev.path) { urls.append(dev) }
        }
        if let extra = try? FileManager.default.contentsOfDirectory(
            at: AppPaths.packsDir, includingPropertiesForKeys: nil) {
            urls += extra.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
        }
        return urls
    }

    func pick(character: FamilyMember, reminder: ReminderKind, stage: Stage, tone: Tone) -> Line? {
        let key = reminder.rawValue

        func pool(matchTone: Bool, allowAny: Bool) -> [Line] {
            lines.filter { line in
                guard line.character == character, line.stage == stage else { return false }
                let reminderOK = line.reminder == key || (allowAny && line.reminder == "any")
                let toneOK = !matchTone || line.tone == nil || line.tone == tone
                return reminderOK && toneOK
            }
        }

        // Most specific first, then relax.
        var candidates = pool(matchTone: true, allowAny: false)
        if candidates.isEmpty { candidates = pool(matchTone: true, allowAny: true) }
        if candidates.isEmpty { candidates = pool(matchTone: false, allowAny: true) }
        guard !candidates.isEmpty else { return nil }

        let fresh = candidates.filter { !recentIDs.contains($0.id) }
        guard let chosen = (fresh.isEmpty ? candidates : fresh).randomElement() else { return nil }

        recentIDs.append(chosen.id)
        if recentIDs.count > recentLimit { recentIDs.removeFirst(recentIDs.count - recentLimit) }
        return chosen
    }
}
