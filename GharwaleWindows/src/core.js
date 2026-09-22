// Gharwale for Windows — the "brain". Same rules as the Mac app (Swift):
// scheduler → quiet rules → who speaks (escalation) → line → overlay.
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

// ---------- Family ----------

const MEMBERS = ["maa", "papa"];
const other = (m) => (m === "maa" ? "papa" : "maa");
const displayName = (m) => (m === "maa" ? "Maa" : "Papa");

// ---------- Reminders ----------

const KINDS = ["goodMorning", "breakfast", "lunch", "dinner", "water", "move", "meeting", "bedtime"];

const TITLES = {
  goodMorning: "Good morning",
  breakfast: "Breakfast",
  lunch: "Lunch",
  dinner: "Dinner",
  water: "Water",
  move: "Get up and move",
  meeting: "Meeting heads-up",
  bedtime: "Bedtime",
};

const isInterval = (k) => k === "water" || k === "move";
const isCalendar = (k) => k === "meeting";
/** Good morning and bedtime come through quiet hours and the daily limit. */
const bypassesQuiet = (k) => k === "goodMorning" || k === "bedtime";

const DEFAULTS = {
  goodMorning: { hour: 8, minute: 30, owner: "maa" },
  breakfast: { hour: 9, minute: 0, owner: "maa" },
  lunch: { hour: 13, minute: 30, owner: "maa" },
  dinner: { hour: 20, minute: 30, owner: "maa" },
  water: { intervalMinutes: 60, owner: "maa" },
  move: { intervalMinutes: 90, owner: "papa" },
  // Off until Google Calendar is connected (then switched on). "Try a reminder" always works.
  meeting: { intervalMinutes: 5, owner: "maa", enabled: false },
  bedtime: { hour: 23, minute: 0, owner: "papa" },
};

function defaultConfig(kind) {
  return { enabled: true, hour: 9, minute: 0, intervalMinutes: 60, owner: "maa", ...DEFAULTS[kind] };
}

function defaultPrefs() {
  return {
    onboarded: false,
    nickname: "beta",
    language: "hinglish", // or "english"
    tone: "soft", // or "strict" (Pro)
    showTranslation: true,
    family: ["maa", "papa"],
    reminders: Object.fromEntries(KINDS.map((k) => [k, defaultConfig(k)])),
    quietStartHour: 22,
    quietEndHour: 8,
    dailyCap: 12,
    snoozeMinutes: 5,
    escalationEnabled: true,
    launchAtLogin: true,
  };
}

// ---------- Storage (JSON files in %APPDATA%\Gharwale) ----------

function readJSON(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

function writeJSON(file, data) {
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
  fs.renameSync(tmp, file);
}

class Store {
  constructor(dir) {
    this.dir = dir;
    fs.mkdirSync(dir, { recursive: true });
    this.prefsFile = path.join(dir, "preferences.json");
    this.stateFile = path.join(dir, "state.json");
    this.prefs = normalizePrefs(readJSON(this.prefsFile));
    this.state = { lastShown: {}, countDay: "", count: 0, licenseKey: null, ...(readJSON(this.stateFile) || {}) };
  }

  setPrefs(next) {
    this.prefs = normalizePrefs(next);
    writeJSON(this.prefsFile, this.prefs);
    return this.prefs;
  }

  saveState() {
    writeJSON(this.stateFile, this.state);
  }

  config(kind) {
    return this.prefs.reminders[kind] || defaultConfig(kind);
  }

  /** Who asks for this reminder. If that parent isn't "at home", the other one does. */
  owner(kind) {
    const o = this.config(kind).owner;
    return this.prefs.family.includes(o) ? o : this.prefs.family[0] || "maa";
  }
}

/** Tolerant: a missing or wrong field falls back to its default, so updates never wipe settings. */
function normalizePrefs(saved) {
  const d = defaultPrefs();
  const p = { ...d };
  if (saved && typeof saved === "object") {
    for (const key of Object.keys(d)) {
      if (key in saved && typeof saved[key] === typeof d[key]) p[key] = saved[key];
    }
  }
  p.family = Array.isArray(p.family) ? p.family.filter((m) => MEMBERS.includes(m)) : d.family;
  if (!p.family.length) p.family = d.family;
  if (!["hinglish", "english"].includes(p.language)) p.language = d.language;
  if (!["soft", "strict"].includes(p.tone)) p.tone = d.tone;
  const clamp = (v, lo, hi, dflt) => (Number.isFinite(v) ? Math.min(hi, Math.max(lo, Math.round(v))) : dflt);
  p.quietStartHour = clamp(p.quietStartHour, 0, 23, d.quietStartHour);
  p.quietEndHour = clamp(p.quietEndHour, 0, 23, d.quietEndHour);
  p.dailyCap = clamp(p.dailyCap, 1, 40, d.dailyCap);
  p.snoozeMinutes = clamp(p.snoozeMinutes, 1, 30, d.snoozeMinutes);
  const savedReminders = (saved && saved.reminders) || {};
  p.reminders = Object.fromEntries(
    KINDS.map((k) => {
      const c = { ...defaultConfig(k), ...(savedReminders[k] || {}) };
      c.hour = clamp(c.hour, 0, 23, 9);
      c.minute = clamp(c.minute, 0, 59, 0);
      c.intervalMinutes = clamp(c.intervalMinutes, 1, 240, 60);
      if (!MEMBERS.includes(c.owner)) c.owner = defaultConfig(k).owner;
      c.enabled = Boolean(c.enabled);
      return [k, c];
    })
  );
  return p;
}

// ---------- Character art ----------

/** Pictures named <member>-<mood>-<n>.png. User art in %APPDATA%\Gharwale\Characters wins. */
class CharacterArt {
  constructor(dirs) {
    this.dirs = dirs;
    this.cache = new Map();
  }

  list(member, mood) {
    const key = `${member}-${mood}`;
    if (this.cache.has(key)) return this.cache.get(key);
    let found = [];
    for (const dir of this.dirs) {
      for (let n = 1; ; n++) {
        const f = path.join(dir, `${key}-${n}.png`);
        if (!fs.existsSync(f)) break;
        found.push(f);
      }
      if (found.length) break;
    }
    this.cache.set(key, found);
    return found;
  }

  /** A random picture for this mood, falling back to neutral. */
  pick(member, mood) {
    const list = this.list(member, mood).length ? this.list(member, mood) : this.list(member, "neutral");
    if (!list.length) return null;
    return pathToFileURL(list[Math.floor(Math.random() * list.length)]).href;
  }
}

// ---------- Content (lines) ----------

class ContentEngine {
  constructor(dirs) {
    this.dirs = dirs;
    this.lines = [];
    this.recent = [];
    this.reload();
  }

  reload() {
    const all = [];
    for (const dir of this.dirs) {
      if (!fs.existsSync(dir)) continue;
      const files = fs.readdirSync(dir).filter((f) => f.endsWith(".json")).sort();
      for (const f of files) {
        const pack = readJSON(path.join(dir, f));
        if (pack && Array.isArray(pack.lines)) all.push(...pack.lines);
        else console.warn(`Gharwale: could not load pack ${f}`);
      }
    }
    this.lines = all;
    console.log(`Gharwale: loaded ${all.length} lines`);
  }

  pick(character, reminder, stage, tone) {
    const pool = (matchTone, allowAny) =>
      this.lines.filter((l) => {
        if (l.character !== character || l.stage !== stage) return false;
        const reminderOK = l.reminder === reminder || (allowAny && l.reminder === "any");
        const toneOK = !matchTone || !l.tone || l.tone === tone;
        return reminderOK && toneOK;
      });

    // Most specific first, then relax.
    let candidates = pool(true, false);
    if (!candidates.length) candidates = pool(true, true);
    if (!candidates.length) candidates = pool(false, true);
    if (!candidates.length) return null;

    const fresh = candidates.filter((l) => !this.recent.includes(l.id));
    const from = fresh.length ? fresh : candidates;
    const chosen = from[Math.floor(Math.random() * from.length)];
    this.recent.push(chosen.id);
    if (this.recent.length > 40) this.recent.splice(0, this.recent.length - 40);
    return chosen;
  }
}

// ---------- Scheduler ----------

const GRACE_MS = 45 * 60 * 1000; // a fixed-time reminder may still show up to 45 min late
const MAX_LEVEL = 3; // stop after this many snoozes

class Scheduler {
  constructor(store) {
    this.store = store;
    this.snoozes = {};
    this.launchedAt = Date.now();
    this.timer = null;
  }

  start(onTick) {
    clearInterval(this.timer);
    const run = () => onTick(new Date());
    run();
    this.timer = setInterval(run, 20 * 1000);
  }

  dueReminders(now, prefs) {
    const t = now.getTime();
    const result = [];

    // Snoozed reminders come back first.
    for (const kind of KINDS) {
      const s = this.snoozes[kind];
      if (s && t >= s.due) result.push({ kind, level: s.level });
    }

    for (const kind of KINDS) {
      const cfg = prefs.reminders[kind];
      if (isCalendar(kind) || this.snoozes[kind] || !cfg || !cfg.enabled) continue;
      const last = this.store.state.lastShown[kind] || 0;

      if (isInterval(kind)) {
        const base = Math.max(last, this.launchedAt);
        if (t - base >= Math.max(cfg.intervalMinutes, 5) * 60 * 1000) result.push({ kind, level: 0 });
      } else {
        const scheduled = new Date(now);
        scheduled.setHours(cfg.hour, cfg.minute, 0, 0);
        const s = scheduled.getTime();
        if (t >= s && t - s < GRACE_MS && last < s) result.push({ kind, level: 0 });
      }
    }
    return result;
  }

  markShown(kind, now) {
    this.store.state.lastShown[kind] = now.getTime();
    delete this.snoozes[kind];
    this.store.saveState();
  }

  /** Brings the reminder back later, one step further along the escalation chain, or drops it. */
  snooze(kind, level, minutes, now) {
    if (level > MAX_LEVEL) {
      delete this.snoozes[kind];
      return;
    }
    this.snoozes[kind] = { due: now.getTime() + minutes * 60 * 1000, level };
  }

  clearSnoozes() {
    this.snoozes = {};
  }
}

// ---------- License (Pro) ----------

/**
 * One-time Pro purchase, verified by license key.
 * Development mode: any key shaped like GHAR-XXXX-XXXX-XXXX is accepted.
 * Before selling, set ACTIVATION_ENDPOINT to your payment provider's activation URL.
 */
const ACTIVATION_ENDPOINT = null;

class License {
  constructor(store) {
    this.store = store;
  }

  get isPro() {
    return Boolean(this.store.state.licenseKey);
  }

  async activate(raw) {
    const trimmed = String(raw || "").trim();
    if (ACTIVATION_ENDPOINT) {
      const res = await fetch(ACTIVATION_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ license_key: trimmed, name: "Windows PC" }),
      });
      if (!res.ok) throw new Error(`The key was not accepted. ${await res.text()}`);
      this.store.state.licenseKey = trimmed;
    } else {
      const key = trimmed.toUpperCase();
      if (!/^GHAR(-[A-Z0-9]{4}){3}$/.test(key)) {
        throw new Error("That key doesn't look right. It should look like GHAR-XXXX-XXXX-XXXX.");
      }
      this.store.state.licenseKey = key;
    }
    this.store.saveState();
  }

  deactivate() {
    this.store.state.licenseKey = null;
    this.store.saveState();
  }
}

// ---------- Coordinator ----------

const IDLE_THRESHOLD = 180; // seconds without input = "away", stay quiet
const ANSWER_TIMEOUT = 25; // seconds before an unanswered bubble counts as ignored

const dayKey = (d) => `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;

class Coordinator {
  constructor({ store, content, art, scheduler, overlay, license, idleSeconds, openLink, onStateChange, calendar = null }) {
    Object.assign(this, { store, content, art, scheduler, overlay, license, idleSeconds, openLink, calendar });
    this.onStateChange = onStateChange || (() => {});
    this.pausedUntil = null;
    this.active = null;
    this.replacements = {};
  }

  start() {
    this.scheduler.start((now) => this.tick(now));
  }

  // ----- Tray menu state -----

  get isPaused() {
    return Boolean(this.pausedUntil && this.pausedUntil > Date.now());
  }

  statusLine() {
    if (this.isPaused) {
      const t = new Date(this.pausedUntil).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      return `Paused until ${t}`;
    }
    const n = this.todayCount();
    return n === 1 ? "1 check-in today" : `${n} check-ins today`;
  }

  pause(minutes) {
    this.pausedUntil = Date.now() + minutes * 60 * 1000;
    this.scheduler.clearSnoozes();
    this.overlay.hide();
    this.onStateChange();
  }

  resume() {
    this.pausedUntil = null;
    this.onStateChange();
  }

  // ----- Tick -----

  tick(now) {
    if (!this.store.prefs.onboarded || this.overlay.isShowing) return;
    if (this.isPaused) return;
    if (this.pausedUntil) {
      this.pausedUntil = null;
      this.onStateChange();
    }

    // Meetings first: they can't wait.
    const meetingCfg = this.store.config("meeting");
    if (this.calendar && meetingCfg.enabled) {
      const meeting = this.calendar.nextMeeting(now, meetingCfg.intervalMinutes);
      if (meeting && this.canShowMeeting()) {
        this.calendar.markAnnounced(meeting);
        this.present("meeting", 0, now, false, meeting);
        return;
      }
    }

    for (const due of this.scheduler.dueReminders(now, this.store.prefs)) {
      if (this.canShow(due.kind, now)) {
        this.present(due.kind, due.level, now, false);
        return;
      }
    }
  }

  canShow(kind, now) {
    const p = this.store.prefs;
    if (!bypassesQuiet(kind)) {
      if (isQuietHour(now, p.quietStartHour, p.quietEndHour)) return false;
      if (this.todayCount() >= p.dailyCap) return false;
    }
    if (this.idleSeconds() > IDLE_THRESHOLD) return false;
    return true;
  }

  /** Meeting heads-ups skip quiet hours and the daily limit, but not if you're away. */
  canShowMeeting() {
    return this.idleSeconds() <= IDLE_THRESHOLD;
  }

  // ----- Presenting -----

  /** Shows a reminder right now, ignoring the rules. Used by "Try a reminder". */
  preview(kind) {
    this.active = null;
    let sample = null;
    if (kind === "meeting") {
      const minutes = this.store.config("meeting").intervalMinutes;
      sample = { title: "Team standup", start: Date.now() + minutes * 60 * 1000, joinURL: null };
    }
    this.present(kind, 0, new Date(), true, sample);
  }

  present(kind, level, now, preview, meeting = null) {
    if (meeting) {
      const minutes = Math.max(1, Math.round((meeting.start - now.getTime()) / 60000));
      this.replacements = { "{meeting}": meeting.title, "{minutes}": String(minutes) };
    } else {
      this.replacements = {};
    }

    const prefs = this.store.prefs;
    const tone = this.effectiveTone();
    const owner = this.store.owner(kind);

    // Escalation: owner asks, owner asks again, then the other parent steps in.
    let speaker = owner;
    let stage = "ask";
    if (level >= 2 && prefs.escalationEnabled && prefs.family.includes(other(owner))) {
      speaker = other(owner);
      stage = "escalate";
    }

    const line =
      this.content.pick(speaker, kind, stage, tone) || this.content.pick(speaker, kind, "ask", tone);
    if (!line) {
      console.warn(`Gharwale: no line for ${speaker}/${kind}`);
      return;
    }

    if (!preview) {
      if (!isCalendar(kind)) this.scheduler.markShown(kind, now);
      this.bumpCount();
      this.onStateChange();
    }
    this.active = { kind, level, speaker, isPreview: preview };

    const primary = this.render(line.character, line.mood, line.text, line.translation);
    let secondary = null;
    const f = line.followup;
    if (f && prefs.family.includes(f.character)) {
      secondary = this.render(f.character, f.mood || "neutral", f.text, f.translation);
    }

    const buttons = [{ title: this.doneTitle(kind, speaker), isPrimary: true, action: () => this.handleDone() }];
    if (isCalendar(kind)) {
      if (meeting && meeting.joinURL) {
        buttons.push({
          title: "Join",
          isPrimary: false,
          action: () => {
            this.openLink(meeting.joinURL);
            this.handleDone();
          },
        });
      }
    } else {
      buttons.push({ title: this.snoozeTitle(kind), isPrimary: false, action: () => this.handleSnooze() });
    }

    this.overlay.show(primary, secondary, buttons, ANSWER_TIMEOUT + (secondary ? 3 : 0), () =>
      this.handleSnooze()
    );
  }

  // ----- Answers -----

  handleDone() {
    const a = this.active;
    if (!a) return this.overlay.hide();
    this.active = null;

    // Sometimes the other parent reacts instead: a small family moment.
    const family = this.store.prefs.family;
    const reactor = family.includes(other(a.speaker)) && Math.floor(Math.random() * 3) === 0 ? other(a.speaker) : a.speaker;

    const line = this.content.pick(reactor, a.kind, "done", this.effectiveTone());
    if (line) this.overlay.react(this.render(line.character, line.mood, line.text, line.translation), 2.6);
    else this.overlay.hide();
  }

  /** Snoozed or ignored: come back later, one step further along the escalation chain. */
  handleSnooze() {
    const a = this.active;
    if (!a) return this.overlay.hide();
    this.active = null;
    // Previews and meetings are never snoozed.
    if (!a.isPreview && !isCalendar(a.kind)) {
      this.scheduler.snooze(a.kind, a.level + 1, this.store.prefs.snoozeMinutes, new Date());
    }
    this.overlay.hide();
  }

  // ----- Helpers -----

  effectiveTone() {
    const t = this.store.prefs.tone;
    return t === "strict" && !this.license.isPro ? "soft" : t;
  }

  render(character, mood, text, translation) {
    const p = this.store.prefs;
    const name = p.nickname.trim() || "beta";
    const fill = (s) => {
      let out = String(s || "").split("{name}").join(name);
      for (const [k, v] of Object.entries(this.replacements)) out = out.split(k).join(v);
      return out;
    };
    const base = { character, name: displayName(character), mood, image: this.art.pick(character, mood) };
    if (p.language === "english") return { ...base, text: fill(translation), subtitle: null };
    return { ...base, text: fill(text), subtitle: p.showTranslation ? fill(translation) : null };
  }

  doneTitle(kind, speaker) {
    const who = displayName(speaker);
    if (kind === "goodMorning") return `Good morning ${who}`;
    if (kind === "bedtime") return `Good night ${who}`;
    return this.store.prefs.language === "hinglish" ? `Theek hai ${who}` : `Okay ${who}`;
  }

  snoozeTitle(kind) {
    const m = this.store.prefs.snoozeMinutes;
    if (kind === "bedtime") return this.store.prefs.language === "hinglish" ? `${m} min aur` : `${m} more min`;
    return `${m} min`;
  }

  todayCount() {
    const s = this.store.state;
    return s.countDay === dayKey(new Date()) ? s.count : 0;
  }

  bumpCount() {
    const s = this.store.state;
    s.count = this.todayCount() + 1;
    s.countDay = dayKey(new Date());
    this.store.saveState();
  }
}

function isQuietHour(date, start, end) {
  if (start === end) return false;
  const h = date.getHours();
  return start < end ? h >= start && h < end : h >= start || h < end;
}

module.exports = {
  MEMBERS,
  KINDS,
  TITLES,
  isInterval,
  isCalendar,
  displayName,
  Store,
  CharacterArt,
  ContentEngine,
  Scheduler,
  License,
  Coordinator,
  isQuietHour,
};
