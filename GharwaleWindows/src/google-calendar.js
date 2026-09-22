// Google Calendar for Windows/Linux: "Sign in with Google", then read upcoming meetings.
//
// How sign-in works (Google's recommended flow for desktop apps):
//  1. We open Google's sign-in page in the user's normal browser.
//  2. Google sends the browser back to a tiny web server on this computer (127.0.0.1).
//  3. We swap the one-time code for tokens (with PKCE, so a stolen code is useless).
// Read-only: Gharwale never creates or changes events. Nothing is sent anywhere except Google.
const http = require("http");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const REVOKE_URL = "https://oauth2.googleapis.com/revoke";
const EVENTS_URL = "https://www.googleapis.com/calendar/v3/calendars/primary/events";
const SCOPES = ["openid", "email", "https://www.googleapis.com/auth/calendar.events.readonly"];

const SIGN_IN_TIMEOUT_MS = 5 * 60 * 1000;
const REFRESH_EVERY_MS = 2 * 60 * 1000;
const LOOK_AHEAD_MS = 3 * 60 * 60 * 1000;

const MEETING_HOSTS = [
  "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
  "webex.com", "whereby.com", "around.co", "gotomeeting.com",
];
// Not real meetings: skip these Google event types.
const SKIP_TYPES = new Set(["workingLocation", "outOfOffice", "focusTime", "birthday"]);

const b64url = (buf) => buf.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

class GoogleCalendar {
  /**
   * @param {object} o
   * @param {string} o.dir        where to keep the (encrypted) sign-in token
   * @param {object} o.config     { clientId, clientSecret } from src/google-config.json
   * @param {object} o.safeStorage Electron safeStorage (Windows DPAPI / Linux keyring)
   * @param {Function} o.openExternal opens a URL in the user's browser
   * @param {Function} [o.onChange] called when connection state changes
   */
  constructor({ dir, config, safeStorage, openExternal, onChange }) {
    this.file = path.join(dir, "google.json");
    this.config = config || {};
    this.safeStorage = safeStorage;
    this.openExternal = openExternal;
    this.onChange = onChange || (() => {});
    this.events = [];
    this.announced = new Set();
    this.access = null; // { token, expiresAt }
    this.saved = this.load(); // { refreshToken, email }
    this.timer = null;
    this.lastError = null;
  }

  get isConfigured() {
    return Boolean(this.config.clientId && this.config.clientSecret);
  }

  get isConnected() {
    return Boolean(this.saved && this.saved.refreshToken);
  }

  status() {
    return {
      configured: this.isConfigured,
      connected: this.isConnected,
      email: this.saved ? this.saved.email : null,
      error: this.lastError,
    };
  }

  // ---------- Keeping the token safe on this computer ----------

  load() {
    try {
      const raw = JSON.parse(fs.readFileSync(this.file, "utf8"));
      const refreshToken = raw.encrypted
        ? this.safeStorage.decryptString(Buffer.from(raw.refreshToken, "base64"))
        : raw.refreshToken;
      return { refreshToken, email: raw.email || null };
    } catch {
      return null;
    }
  }

  save(refreshToken, email) {
    const canEncrypt = this.safeStorage && this.safeStorage.isEncryptionAvailable();
    const stored = canEncrypt ? this.safeStorage.encryptString(refreshToken).toString("base64") : refreshToken;
    fs.writeFileSync(this.file, JSON.stringify({ encrypted: canEncrypt, refreshToken: stored, email }, null, 2));
    this.saved = { refreshToken, email };
  }

  forget() {
    try {
      fs.unlinkSync(this.file);
    } catch {}
    this.saved = null;
    this.access = null;
    this.events = [];
  }

  // ---------- Sign in / sign out ----------

  async connect() {
    if (!this.isConfigured) throw new Error("Google sign-in isn't set up in this version of Gharwale yet.");
    this.lastError = null;

    const verifier = b64url(crypto.randomBytes(32));
    const challenge = b64url(crypto.createHash("sha256").update(verifier).digest());
    const state = b64url(crypto.randomBytes(16));

    const { code, redirectUri } = await this.waitForCode(state, challenge);
    const tokens = await this.post(TOKEN_URL, {
      code,
      client_id: this.config.clientId,
      client_secret: this.config.clientSecret,
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
      code_verifier: verifier,
    });
    if (!tokens.refresh_token) throw new Error("Google didn't send a sign-in token. Please try again.");

    this.save(tokens.refresh_token, emailFromIdToken(tokens.id_token));
    this.access = { token: tokens.access_token, expiresAt: Date.now() + (tokens.expires_in - 60) * 1000 };
    await this.refresh();
    this.start();
    this.onChange();
    return this.status();
  }

  async disconnect() {
    const token = this.saved && this.saved.refreshToken;
    this.stop();
    this.forget();
    this.onChange();
    if (token) {
      // Tell Google to cancel access too (best effort).
      try {
        await this.post(REVOKE_URL, { token });
      } catch {}
    }
    return this.status();
  }

  /** Opens Google in the browser and waits for it to send the user back to 127.0.0.1. */
  waitForCode(state, challenge) {
    return new Promise((resolve, reject) => {
      let redirectUri;
      const server = http.createServer((req, res) => {
        const url = new URL(req.url, redirectUri);
        if (url.pathname !== "/") {
          res.writeHead(404).end();
          return;
        }
        const error = url.searchParams.get("error");
        const code = url.searchParams.get("code");
        const ok = !error && code && url.searchParams.get("state") === state;
        res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        res.end(resultPage(ok));
        finish();
        if (ok) resolve({ code, redirectUri });
        else reject(new Error(error === "access_denied" ? "Sign-in was cancelled." : "Google sign-in didn't finish. Please try again."));
      });

      const timeout = setTimeout(() => {
        finish();
        reject(new Error("Sign-in took too long. Please try again."));
      }, SIGN_IN_TIMEOUT_MS);

      function finish() {
        clearTimeout(timeout);
        server.close();
      }

      server.on("error", (err) => {
        finish();
        reject(err);
      });

      server.listen(0, "127.0.0.1", () => {
        redirectUri = `http://127.0.0.1:${server.address().port}`;
        const params = new URLSearchParams({
          client_id: this.config.clientId,
          redirect_uri: redirectUri,
          response_type: "code",
          scope: SCOPES.join(" "),
          code_challenge: challenge,
          code_challenge_method: "S256",
          state,
          access_type: "offline",
          prompt: "consent",
        });
        this.openExternal(`${AUTH_URL}?${params}`);
      });
    });
  }

  // ---------- Reading meetings ----------

  start() {
    this.stop();
    if (!this.isConnected) return;
    this.refresh().catch(() => {});
    this.timer = setInterval(() => this.refresh().catch(() => {}), REFRESH_EVERY_MS);
  }

  stop() {
    clearInterval(this.timer);
    this.timer = null;
  }

  async accessToken() {
    if (this.access && Date.now() < this.access.expiresAt) return this.access.token;
    try {
      const t = await this.post(TOKEN_URL, {
        client_id: this.config.clientId,
        client_secret: this.config.clientSecret,
        refresh_token: this.saved.refreshToken,
        grant_type: "refresh_token",
      });
      this.access = { token: t.access_token, expiresAt: Date.now() + (t.expires_in - 60) * 1000 };
      return this.access.token;
    } catch (err) {
      // Access was removed in the Google account, or the token expired: sign out cleanly.
      if (/invalid_grant/.test(err.message)) {
        this.stop();
        this.forget();
        this.lastError = "Google Calendar was disconnected. Please connect again.";
        this.onChange();
      }
      throw err;
    }
  }

  async refresh() {
    if (!this.isConnected) return;
    const now = Date.now();
    const params = new URLSearchParams({
      timeMin: new Date(now).toISOString(),
      timeMax: new Date(now + LOOK_AHEAD_MS).toISOString(),
      singleEvents: "true", // expands repeating meetings like a daily standup
      orderBy: "startTime",
      maxResults: "25",
    });
    const res = await fetch(`${EVENTS_URL}?${params}`, {
      headers: { Authorization: `Bearer ${await this.accessToken()}` },
    });
    if (!res.ok) {
      this.lastError = `Couldn't read Google Calendar (${res.status}).`;
      throw new Error(this.lastError);
    }
    const data = await res.json();
    this.events = (data.items || []).map(toMeeting).filter(Boolean);
    this.lastError = null;
  }

  /** The next meeting starting within `leadMinutes` that hasn't been announced yet. */
  nextMeeting(now, leadMinutes) {
    if (!this.isConnected) return null;
    const t = now.getTime();
    const lead = Math.max(leadMinutes, 1) * 60 * 1000;
    return this.events.find((m) => m.start > t && m.start - t <= lead && !this.announced.has(m.key)) || null;
  }

  markAnnounced(meeting) {
    if (this.announced.size > 500) this.announced.clear();
    this.announced.add(meeting.key);
  }

  // ---------- Helpers ----------

  async post(url, body) {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(body),
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`${res.status} ${text}`);
    return text ? JSON.parse(text) : {};
  }
}

/** Google event → { key, title, start (ms), joinURL } — or null to skip it. */
function toMeeting(e) {
  if (!e || e.status === "cancelled") return null;
  if (!e.start || !e.start.dateTime) return null; // all-day event
  if (SKIP_TYPES.has(e.eventType)) return null;
  const me = (e.attendees || []).find((a) => a.self);
  if (me && me.responseStatus === "declined") return null;

  const start = Date.parse(e.start.dateTime);
  return {
    key: `${e.id}|${start}`,
    title: cleanTitle(e.summary),
    start,
    joinURL: joinURL(e),
  };
}

function cleanTitle(raw) {
  const t = String(raw || "").trim();
  if (!t) return "meeting";
  return t.length > 40 ? `${t.slice(0, 38)}…` : t;
}

function joinURL(e) {
  const candidates = [];
  if (e.hangoutLink) candidates.push(e.hangoutLink);
  for (const p of (e.conferenceData && e.conferenceData.entryPoints) || []) {
    if (p.entryPointType === "video" && p.uri) candidates.push(p.uri);
  }
  const text = `${e.location || ""}\n${e.description || ""}`;
  candidates.push(...(text.match(/https?:\/\/[^\s"'<>)\]]+/g) || []));

  return (
    candidates.find((u) => {
      try {
        const host = new URL(u).hostname.toLowerCase();
        return MEETING_HOSTS.some((h) => host === h || host.endsWith(`.${h}`));
      } catch {
        return false;
      }
    }) || null
  );
}

function emailFromIdToken(idToken) {
  try {
    const payload = JSON.parse(Buffer.from(idToken.split(".")[1], "base64").toString("utf8"));
    return payload.email || null;
  } catch {
    return null;
  }
}

function resultPage(ok) {
  const title = ok ? "You're connected" : "Sign-in didn't finish";
  const body = ok
    ? "Maa and Papa can now see your meetings. You can close this tab."
    : "Please go back to Gharwale and try again.";
  return `<!doctype html><meta charset="utf-8"><title>Gharwale</title>
<body style="margin:0;height:100vh;display:grid;place-items:center;background:#f6f4f0;font-family:Segoe UI,system-ui,sans-serif;color:#161412">
<div style="text-align:center;max-width:420px;padding:32px;background:#fff;border:1px solid #e6e1d9;border-radius:20px">
<div style="font-size:40px">${ok ? "✅" : "⚠️"}</div><h1 style="font-size:22px;margin:12px 0 6px">${title}</h1>
<p style="color:#6f6a63;margin:0">${body}</p></div></body>`;
}

module.exports = { GoogleCalendar, toMeeting, joinURL };
