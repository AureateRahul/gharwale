# CLAUDE.md

Guidance for Claude when working in this project.

## How to talk to me

- Always explain things in simple terms and plain English.
- Avoid heavy jargon. If a technical word is needed, explain what it means in one short line.

## Project goal

- This project builds **notifications / stickers** that look and work like the ones on a reference website.
- The reference website link will be shared later. When it is shared, add it below and use it as the design guide.

## Reference website

- https://www.maaa.app/ — use for **layout, section order and feel only**.
- Do NOT copy their text, logo, images or brand name. Our brand is **MaaBaap**, with our own words.

## Mac app (Gharwale)

- The real Mac app is called **Gharwale**. It is Swift code, made in a separate Claude web chat, and built on the user's iMac with `./scripts/build-app.sh` → `build/Gharwale.app`.
- Needs macOS 13 (Ventura) or later. Reads the Mac Calendar for meeting reminders.
- The website's "Download for Mac" buttons point to `downloads/Gharwale.dmg`, made on the Mac with `UNIVERSAL=1 ./scripts/build-app.sh && ./scripts/make-dmg.sh` inside `Gharwale/`.
- App source code lives in `Gharwale/` (Swift). Don't put it on the public website server.
- **Windows + Linux app** lives in `GharwaleWindows/` (one Electron app, JavaScript). Linux: `npm run dist:linux` (must run on Linux) → `downloads/Gharwale.AppImage` + `downloads/gharwale_amd64.deb`. Linux-only code paths are behind `isLinux` in `main.js` (window shape instead of click-through, autostart .desktop file).
- **GitHub Actions** (`.github/workflows/build-apps.yml`) builds Linux, Windows and Mac in the cloud; a `v*` tag makes a GitHub Release with fixed file names.
- Same rules, lines and art as the Mac app; art and `core.json` are copied from `Gharwale/` by `npm run sync`.
  - Build the installer: `cd GharwaleWindows && npm run dist` → `dist/Gharwale-Setup-<version>.exe`, also copied to `downloads/Gharwale-Setup.exe` for the website button.
  - Test run: `npm start`. Inside VS Code, the env var `ELECTRON_RUN_AS_NODE=1` is set and stops Electron opening windows — unset it first (`env -u ELECTRON_RUN_AS_NODE`).
  - If the build fails with "Cannot create symbolic link", unpack the winCodeSign archive into `%LOCALAPPDATA%\electron-builder\Cache\winCodeSign\winCodeSign-2.6.0` without its `darwin` folder.
  - Not on Windows yet: calendar meeting reminders, full-screen and on-a-call detection.
- Maa and Papa character art belongs to the user. The website uses copies in `images/characters/` (same names as `Gharwale/Characters/`). The art has a black background, so on light areas it sits inside black rounded tiles.

## Files

- `index.html` — the landing page (sections: hero with notch sticker, features, language/tone picker, privacy, how it works, pricing, reviews, final CTA).
- `styles.css` — all styling.
- `script.js` — notch animation, language/tone/colour picker, scroll fade-in.
- Open `index.html` in a browser to view. No build step needed.
