# Gharwale for Windows and Linux

The Windows and Linux version of Gharwale (one Electron app for both). Maa and Papa drop down from the top of the screen to remind you to eat, drink water, move and sleep. It follows the same rules as the Mac app in `../Gharwale` and uses the same lines and character art.

## For users

Download `Gharwale-Setup.exe`, double-click it, and it installs and opens. You don't need to set anything up. A welcome window asks three quick questions, then Maa says good morning. Gharwale lives in the tray near the clock; click its icon for **Pause**, **Try a reminder** and **Settings**.

## Linux

Two files are built:
- **Gharwale.AppImage** runs on almost any Linux. Right-click it → Properties → Permissions → "Allow executing as program" (or `chmod +x Gharwale.AppImage`), then double-click it.
- **gharwale_amd64.deb** is for Ubuntu, Debian and Linux Mint. Double-click it to install, or run `sudo apt install ./gharwale_amd64.deb`.

Linux differences, handled in code:
- The pop-up window is cut to the shape of the tab + bubble (`setShape`), because Linux can't pass clicks through a see-through window the way Windows does.
- "Start when you log in" writes `~/.config/autostart/gharwale.desktop`.
- The tray icon is 24px.

Known limits on Linux:
- **GNOME (Fedora, plain GNOME)** hides tray icons unless the "AppIndicator" extension is on (Ubuntu has it by default). Without it, open Gharwale again from the app menu to get Settings.
- On **Wayland**, apps can't choose where their windows go, so the pop-up may not sit at the top-centre. Electron runs through XWayland by default, which keeps it working on most systems.
- Before publishing the .deb, change the placeholder email `change-me@example.com` in `package.json` (`author` and `build.linux.maintainer`).

Building Linux files needs Linux. Use the GitHub Actions workflow (below), a Linux PC, or WSL. On Windows, `electron-builder` can't build `.deb`, and it can only build `.AppImage` with Windows Developer Mode turned on.

## Build all platforms on GitHub (free)

`.github/workflows/build-apps.yml` builds **Linux (.AppImage + .deb)**, **Windows (.exe)** and **Mac (.dmg)** on GitHub's computers.
- **Test build:** GitHub → Actions → *Build apps* → *Run workflow*. The files appear under the run's *Artifacts*.
- **Release:** push a tag like `v0.1.0`. The files are attached to a GitHub Release with fixed names, so the website can link to `https://github.com/<you>/<repo>/releases/latest/download/Gharwale-Setup.exe` (and `Gharwale.AppImage`, `gharwale_amd64.deb`, `Gharwale.dmg`).

## For you (the developer)

You need Node.js 18 or newer.

```bash
npm install          # first time only
npm start            # run the app from source
npm run dist         # Windows: build dist/Gharwale-Setup-<version>.exe and copy it to ../downloads/
npm run dist:linux   # Linux (run on Linux): build .AppImage + .deb and copy them to ../downloads/
```

`npm run sync`, which runs automatically before `start` and `dist`, copies `Characters/*.png` and `ContentPacks/*.json` from the Mac app. Edit lines and art in `../Gharwale` and both apps pick them up.

To release a new version, raise `"version"` in `package.json` and run `npm run dist`.

### Where things live

| What | File |
| --- | --- |
| Reminder rules, escalation, lines, settings, Pro key | `src/core.js` (same logic as the Swift files) |
| Tray icon, pop-up window, settings windows | `main.js` |
| The black tab and speech bubble | `src/overlay.*` |
| Settings / welcome screens | `src/settings.*`, `src/onboarding.*`, `src/ui.css` |

User data is stored in `%APPDATA%\Gharwale`: `preferences.json` holds the settings and `state.json` holds today's count, when each reminder last showed, and the license key. Extra art goes in `%APPDATA%\Gharwale\Characters` and extra line packs in `%APPDATA%\Gharwale\Packs`, the same as on Mac.

### Gotchas

- **Inside VS Code** the variable `ELECTRON_RUN_AS_NODE=1` is set, and it stops Electron opening windows (`app` is undefined). Run `env -u ELECTRON_RUN_AS_NODE npm start` or use a normal terminal.
- **"Cannot create symbolic link" during `npm run dist`**: electron-builder's `winCodeSign` download contains macOS symlinks that Windows can't create without admin rights. Unpack it once without the `darwin` folder into `%LOCALAPPDATA%\electron-builder\Cache\winCodeSign\winCodeSign-2.6.0`, or turn on Windows Developer Mode.

## Before public launch

- **Code signing.** Without a code-signing certificate, Windows SmartScreen shows "Windows protected your PC", and users must click **More info → Run anyway**. A certificate (from Certum, Sectigo or Azure Trusted Signing) removes this. Put it in `build.win` in `package.json`.
- **Calendar meeting reminders** aren't on Windows yet. The Mac uses Apple's Calendar and Windows has no equivalent. The plan is a Google or Outlook calendar link (ICS) or sign-in. "Try a reminder → Meeting heads-up" already works.
- **Full-screen and on-a-call detection** aren't on Windows yet. The app already stays quiet when you've been away for 3 minutes.
- **Pro keys** are in development mode, the same as on Mac: set `ACTIVATION_ENDPOINT` in `src/core.js`.
