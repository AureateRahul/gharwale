# Gharwale — MVP

The whole Indian family lives in your Mac's notch. This is the MVP from the product blueprint: macOS only, Maa and Papa, seven reminders, Hinglish and English, Soft and Strict tones, the escalation chain, and calm rules so they never become annoying.

## Build and run

You need macOS 13 (Ventura) or later and either Xcode 14.3+ or just the Command Line Tools (`xcode-select --install`). The build script calls the Swift compiler directly, so full Xcode is not required.

```bash
cd Gharwale
./scripts/build-app.sh
open build/Gharwale.app
```

A house icon appears in the menu bar and the 3-step onboarding opens. When you finish it, Maa says good morning from the notch. Use **menu bar → Try a reminder** to see any reminder immediately.

With full Xcode installed you can also use `swift run` from the repo root (the core pack is read from `ContentPacks/`). Launch-at-login only works from the bundled `.app`.

To open it in Xcode, run `open Package.swift`.

## Make the download file (DMG)

This makes `build/Gharwale.dmg`, the file people download from the website, open, and drag to Applications. It runs on Apple Silicon and Intel Macs.

```bash
UNIVERSAL=1 ./scripts/build-app.sh && ./scripts/make-dmg.sh
```

With an Apple Developer account, add signing and notarization so other Macs open it with no warning:

```bash
UNIVERSAL=1 ./scripts/build-app.sh
SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="gharwale" ./scripts/make-dmg.sh
```

`make-dmg.sh` re-signs the app with the hardened runtime and the Calendar entitlement from `scripts/Gharwale.entitlements`, which notarization needs.

## What's included

| Blueprint item | Where it lives |
| --- | --- |
| Notch overlay that grows out of the notch, floating pill on Macs without one | `Overlay.swift` |
| Maa and Papa with 5 moods (neutral, happy, stern, worried, proud) | `CharacterFace.swift` |
| 7 reminders: good morning, breakfast, lunch, dinner, water, move, bedtime | `Models.swift`, `Scheduler.swift` |
| Escalation: owner asks → asks again → other parent steps in | `Coordinator.swift` |
| Tag-team lines (second parent chimes in) and reactions after "Theek hai" | `Coordinator.swift`, `ContentPacks/core.json` |
| Quiet hours, daily cap, snooze, no backlog | `Scheduler.swift`, `Coordinator.swift` |
| Silent while idle, in full-screen apps, or with Zoom / Teams / FaceTime / Keynote in front | `Scheduler.swift` (`SystemSensors`) |
| Hinglish with English line underneath, or English only | `Coordinator.swift` (`render`) |
| Soft tone free, Strict tone Pro | `Settings.swift` (`LicenseManager`) |
| Settings window and 3-step onboarding | `SettingsViews.swift` |
| Menu bar: pause 1 hour, try a reminder, settings | `GharwaleApp.swift` |

## Meeting reminders (Calendar)

Maa or Papa pops up a few minutes before each meeting (5 by default), names the meeting, and shows a **Join** button when the invite has a Zoom, Google Meet, Teams or Webex link.

- Connect from **Settings → Calendar → Connect Calendar** (or the last onboarding step) and allow access in the macOS prompt.
- It reads the calendars in the macOS Calendar app, so to include Google or Outlook, add that account in **System Settings → Internet Accounts** and turn on Calendars.
- All-day events, cancelled events and invites you declined are skipped. Each meeting is announced once, is never snoozed, and comes through quiet hours, the daily cap and full-screen apps, but not while you're away or already on a call.
- Code: `CalendarWatcher.swift`; lines use `{meeting}` and `{minutes}` placeholders.
- When you move to Developer ID signing with the hardened runtime, add the `com.apple.security.personal-information.calendars` entitlement.

## Character art

Mood images live in `Characters/`, named `<member>-<mood>-<n>.png` (for example `maa-happy-1.png`, `maa-happy-2.png`). Moods are `neutral`, `happy`, `stern`, `worried` and `proud`; when a mood has several images, one is picked at random each time. The art has a black background, which blends into the black notch island.

To try new art without rebuilding, put files with the same names in `~/Library/Application Support/Gharwale/Characters/`; they take priority over the bundled ones. If a mood has no image, the app falls back to the drawn face.

## Adding lines

All dialogue lives in `ContentPacks/core.json` (54 lines). Each line has a character, reminder (or `"any"`), stage (`ask`, `escalate`, `done`), optional tone, mood, Hinglish text and English translation. `{name}` becomes the user's nickname. A line can carry a `followup` from the other parent.

Users (or you, while testing) can also drop extra `.json` packs into `~/Library/Application Support/Gharwale/Packs/` and they load on next launch, with no rebuild needed. This is the base for future language and character packs.

## Pro licensing

`LicenseManager` currently runs in development mode: any key shaped like `GHAR-ABCD-EFGH-IJKL` unlocks Pro locally. Before selling, set `LicenseManager.activationEndpoint` to your payment provider's license-activation URL (Dodo Payments, Lemon Squeezy or Gumroad) and match the request body to their API docs.

## Known gaps before public launch

- **Not yet compiled.** This code was written in an environment without macOS or Xcode, so the first build may need small fixes. Compiler errors will point straight at them.
- **Full-screen detection** can also trigger for a maximised window on notched Macs with the Dock hidden. The effect is only fewer reminders, never more.
- **Screen sharing** is detected through the do-not-disturb app list, not the system's sharing state.
- **Distribution:** the build script signs ad-hoc. For public release, sign with a Developer ID (`SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh`) and notarize, otherwise users see the "app is damaged" warning.
- **Windows build** is planned for v1.1, per the roadmap.
