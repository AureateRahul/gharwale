// Gharwale for Windows — app entry: tray icon, overlay window, settings and onboarding.
const { app, BrowserWindow, Tray, Menu, ipcMain, nativeImage, powerMonitor, safeStorage, screen, shell } = require("electron");
const fs = require("fs");
const os = require("os");
const path = require("path");
const core = require("./src/core");
const { GoogleCalendar } = require("./src/google-calendar");

// Only one copy of the app at a time; opening it again shows Settings.
if (!app.requestSingleInstanceLock()) {
  app.quit();
  process.exit(0);
}
app.setAppUserModelId("app.gharwale.windows");

const isLinux = process.platform === "linux";
// Linux needs this for the see-through pop-up window.
if (isLinux) app.commandLine.appendSwitch("enable-transparent-visuals");

const ASSETS = path.join(__dirname, "assets");
const PRELOAD = path.join(__dirname, "preload.js");
const page = (name) => path.join(__dirname, "src", name);

let store, license, coordinator, overlay, tray, art, calendar;
let settingsWin = null;
let onboardingWin = null;

// ---------- Overlay: the black tab at the top of the screen ----------

const PANEL = { width: 820, height: 380 };

class OverlayController {
  constructor() {
    this.win = null;
    this.ready = null;
    this.isShowing = false;
    this.timers = [];
    this.actions = new Map();
  }

  ensureWindow() {
    if (this.win && !this.win.isDestroyed()) return;
    this.win = new BrowserWindow({
      ...PANEL,
      show: false,
      frame: false,
      transparent: true,
      backgroundColor: "#00000000",
      resizable: false,
      movable: false,
      minimizable: false,
      maximizable: false,
      fullscreenable: false,
      skipTaskbar: true,
      focusable: false, // never steals focus from what you're typing in
      hasShadow: false,
      alwaysOnTop: true,
      webPreferences: { preload: PRELOAD, contextIsolation: true, nodeIntegration: false },
    });
    this.win.setAlwaysOnTop(true, "screen-saver");
    this.win.setVisibleOnAllWorkspaces(true);
    // Windows: clicks pass through, except on the bubble (the page tells us when the mouse is over it).
    // Linux can't do that, so the window is cut to the shape of the tab + bubble instead (see setShape).
    if (!isLinux) this.win.setIgnoreMouseEvents(true, { forward: true });
    this.ready = new Promise((resolve) => this.win.webContents.once("did-finish-load", resolve));
    this.win.loadFile(page("overlay.html"));
  }

  /** Top-centre of the main screen. */
  position() {
    const { x, y, width } = screen.getPrimaryDisplay().bounds;
    this.win.setBounds({ x: Math.round(x + width / 2 - PANEL.width / 2), y, ...PANEL });
  }

  later(ms, fn) {
    this.timers.push(setTimeout(fn, ms));
  }

  clear() {
    this.timers.forEach(clearTimeout);
    this.timers = [];
  }

  send(channel, data) {
    if (this.win && !this.win.isDestroyed()) this.win.webContents.send(channel, data);
  }

  async show(primary, secondary, buttons, timeoutSeconds, onTimeout) {
    this.clear();
    this.isShowing = true;
    this.ensureWindow();
    await this.ready;
    this.position();
    this.actions = new Map(buttons.map((b, i) => [String(i), b.action]));
    this.win.showInactive();
    this.send("show", {
      primary,
      buttons: buttons.map((b, i) => ({ id: String(i), title: b.title, primary: b.isPrimary })),
    });
    if (secondary) this.later(1800, () => this.send("secondary", secondary));
    this.later(timeoutSeconds * 1000, () => {
      this.hide();
      onTimeout();
    });
  }

  /** Swaps the bubble for a reaction line, then tucks away. */
  react(utterance, hideAfterSeconds) {
    this.clear();
    this.actions.clear();
    this.send("react", utterance);
    this.later(hideAfterSeconds * 1000, () => this.hide());
  }

  hide() {
    this.clear();
    this.send("hide");
    // Wait for the close animation, then hide the window.
    this.later(700, () => {
      if (this.win && !this.win.isDestroyed()) {
        if (!isLinux) this.win.setIgnoreMouseEvents(true, { forward: true });
        this.win.hide();
      }
      this.isShowing = false;
    });
  }

  press(id) {
    const action = this.actions.get(String(id));
    if (!action) return;
    this.actions.clear();
    action();
  }

  setInteractive(on) {
    if (isLinux) return;
    if (this.win && !this.win.isDestroyed()) this.win.setIgnoreMouseEvents(!on, { forward: true });
  }

  /** Linux: only the tab and bubble areas are part of the window, the rest is truly empty. */
  setShape(rects) {
    if (!isLinux || !this.win || this.win.isDestroyed() || !Array.isArray(rects) || !rects.length) return;
    const clean = rects.map((r) => ({
      x: Math.max(0, Math.round(r.x)),
      y: Math.max(0, Math.round(r.y)),
      width: Math.round(r.width),
      height: Math.round(r.height),
    }));
    this.win.setShape(clean);
  }
}

// ---------- Tray (icon near the clock) ----------

function trayIcon() {
  const img = nativeImage.createFromPath(path.join(ASSETS, "Characters", "maa-happy-1.png"));
  const size = isLinux ? 24 : 16; // Linux panels use bigger tray icons
  return img.isEmpty() ? img : img.resize({ width: size, height: size, quality: "best" });
}

function buildTrayMenu() {
  if (!tray) return;
  const tryItems = core.KINDS.map((kind) => ({
    label: core.TITLES[kind],
    click: () => coordinator.preview(kind),
  }));
  const menu = Menu.buildFromTemplate([
    { label: coordinator.statusLine(), enabled: false },
    { type: "separator" },
    coordinator.isPaused
      ? { label: "Resume reminders", click: () => coordinator.resume() }
      : { label: "Pause for 1 hour", click: () => coordinator.pause(60) },
    { label: "Try a reminder", submenu: tryItems },
    { type: "separator" },
    { label: "Settings…", click: openSettings },
    { label: "Quit Gharwale", click: () => app.quit() },
  ]);
  tray.setContextMenu(menu);
  tray.setToolTip(`Gharwale — ${coordinator.statusLine()}`);
}

// ---------- Windows: settings + onboarding ----------

function makeWindow(file, opts) {
  const win = new BrowserWindow({
    show: false,
    autoHideMenuBar: true,
    backgroundColor: "#f6f4f0",
    icon: path.join(ASSETS, "Characters", "maa-happy-1.png"),
    webPreferences: { preload: PRELOAD, contextIsolation: true, nodeIntegration: false },
    ...opts,
  });
  win.setMenuBarVisibility(false);
  win.loadFile(page(file));
  win.once("ready-to-show", () => win.show());
  return win;
}

function openSettings() {
  if (settingsWin && !settingsWin.isDestroyed()) {
    settingsWin.show();
    settingsWin.focus();
    return;
  }
  settingsWin = makeWindow("settings.html", { width: 580, height: 760, minWidth: 480, minHeight: 500, title: "Gharwale Settings" });
  settingsWin.on("closed", () => (settingsWin = null));
}

function openOnboarding() {
  onboardingWin = makeWindow("onboarding.html", { width: 540, height: 700, resizable: false, maximizable: false, title: "Welcome to Gharwale" });
  onboardingWin.on("closed", () => (onboardingWin = null));
}

function applyLaunchAtLogin(on) {
  // Only the installed app registers itself; a dev run would register electron.exe.
  if (!app.isPackaged) return;
  if (!isLinux) return app.setLoginItemSettings({ openAtLogin: on });

  // Linux: a .desktop file in ~/.config/autostart. For an AppImage, start the AppImage itself.
  const dir = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config"), "autostart");
  const file = path.join(dir, "gharwale.desktop");
  try {
    if (on) {
      const exec = process.env.APPIMAGE || process.execPath;
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(
        file,
        ["[Desktop Entry]", "Type=Application", "Name=Gharwale", `Exec="${exec}"`, "X-GNOME-Autostart-enabled=true", "Terminal=false", ""].join("\n")
      );
    } else if (fs.existsSync(file)) {
      fs.unlinkSync(file);
    }
  } catch (err) {
    console.warn(`Gharwale: autostart change failed: ${err.message}`);
  }
}

// ---------- IPC (pages talking to the app) ----------

function publicState() {
  return {
    prefs: store.prefs,
    isPro: license.isPro,
    platform: process.platform,
    calendar: calendar.status(),
    kinds: core.KINDS.map((k) => ({ id: k, title: core.TITLES[k], interval: core.isInterval(k), calendar: core.isCalendar(k) })),
    faces: {
      maaHappy: art.pick("maa", "happy"),
      maaProud: art.pick("maa", "proud"),
      papaNeutral: art.pick("papa", "neutral"),
      papaStern: art.pick("papa", "stern"),
    },
  };
}

function registerIpc() {
  ipcMain.handle("state:get", () => publicState());

  ipcMain.handle("prefs:set", (_e, next) => {
    let message = null;
    if (next && next.tone === "strict" && !license.isPro) {
      next = { ...next, tone: "soft" };
      message = "Strict tone is part of Pro.";
    }
    const before = store.prefs.launchAtLogin;
    store.setPrefs(next);
    if (store.prefs.launchAtLogin !== before) applyLaunchAtLogin(store.prefs.launchAtLogin);
    buildTrayMenu();
    return { prefs: store.prefs, message };
  });

  ipcMain.handle("license:activate", async (_e, key) => {
    try {
      await license.activate(key);
      return { ok: true, isPro: true, message: "Pro is active. Strict Papa says thank you." };
    } catch (err) {
      return { ok: false, isPro: license.isPro, message: err.message };
    }
  });

  ipcMain.handle("license:deactivate", () => {
    license.deactivate();
    return { ok: true, isPro: false };
  });

  ipcMain.handle("onboarding:finish", (_e, next) => {
    store.setPrefs({ ...next, onboarded: true });
    applyLaunchAtLogin(store.prefs.launchAtLogin);
    if (onboardingWin && !onboardingWin.isDestroyed()) onboardingWin.close();
    // First hello right after onboarding.
    setTimeout(() => coordinator.preview("goodMorning"), 600);
    return true;
  });

  ipcMain.handle("calendar:connect", async () => {
    try {
      await calendar.connect();
      // Connecting means "yes, remind me before meetings".
      const r = store.prefs.reminders;
      store.setPrefs({ ...store.prefs, reminders: { ...r, meeting: { ...r.meeting, enabled: true } } });
      return { ok: true, state: publicState() };
    } catch (err) {
      return { ok: false, message: err.message, state: publicState() };
    }
  });

  ipcMain.handle("calendar:disconnect", async () => {
    await calendar.disconnect();
    return { ok: true, state: publicState() };
  });

  ipcMain.on("overlay:button", (_e, id) => overlay.press(id));
  ipcMain.on("overlay:interactive", (_e, on) => overlay.setInteractive(Boolean(on)));
  ipcMain.on("overlay:shape", (_e, rects) => overlay.setShape(rects));
}

/** Google sign-in keys, written at build time into src/google-config.json (never committed). */
function readGoogleConfig() {
  try {
    return JSON.parse(fs.readFileSync(path.join(__dirname, "src", "google-config.json"), "utf8"));
  } catch {
    return {};
  }
}

// ---------- Start ----------

app.on("second-instance", () => (store && store.prefs.onboarded ? openSettings() : onboardingWin && onboardingWin.focus()));

// A tray app keeps running when its windows close.
app.on("window-all-closed", (e) => e.preventDefault());

app.whenReady().then(() => {
  const userData = app.getPath("userData"); // %APPDATA%\Gharwale
  store = new core.Store(userData);
  license = new core.License(store);
  art = new core.CharacterArt([path.join(userData, "Characters"), path.join(ASSETS, "Characters")]);
  const content = new core.ContentEngine([path.join(ASSETS, "ContentPacks"), path.join(userData, "Packs")]);
  overlay = new OverlayController();
  calendar = new GoogleCalendar({
    dir: userData,
    config: readGoogleConfig(),
    safeStorage,
    openExternal: (url) => shell.openExternal(url),
    onChange: () => settingsWin && !settingsWin.isDestroyed() && settingsWin.webContents.send("calendar:changed"),
  });

  coordinator = new core.Coordinator({
    store,
    content,
    art,
    scheduler: new core.Scheduler(store),
    overlay,
    license,
    idleSeconds: () => powerMonitor.getSystemIdleTime(),
    openLink: (url) => shell.openExternal(url),
    onStateChange: () => buildTrayMenu(),
    calendar,
  });

  tray = new Tray(trayIcon());
  // Windows: left-click opens the menu too. Linux panels already open it on click.
  if (!isLinux) tray.on("click", () => tray.popUpContextMenu());
  buildTrayMenu();
  registerIpc();

  // Keep the menu's "check-ins today" fresh after midnight.
  setInterval(buildTrayMenu, 5 * 60 * 1000);
  screen.on("display-metrics-changed", () => overlay.win && !overlay.win.isDestroyed() && overlay.position());

  coordinator.start();
  calendar.start();
  if (!store.prefs.onboarded) openOnboarding();
});
