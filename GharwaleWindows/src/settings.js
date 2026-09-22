// Settings window. Every change is sent to the app right away.
const $ = (id) => document.getElementById(id);
let state;

const el = (tag, props = {}, ...children) => {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children);
  return node;
};

const hourLabel = (h) => new Date(2000, 0, 1, h).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
const pad = (n) => String(n).padStart(2, "0");

function toast(msg) {
  $("toast").textContent = msg || "";
}

async function save() {
  const r = await gw.invoke("prefs:set", state.prefs);
  state.prefs = r.prefs;
  if (r.message) {
    toast(r.message);
    render();
  }
}

function switchEl(checked, onChange) {
  const input = el("input", { type: "checkbox", checked });
  input.addEventListener("change", () => onChange(input.checked));
  return el("span", { className: "switch" }, input, el("span"));
}

function renderFamily() {
  $("family").replaceChildren(
    ...["maa", "papa"].map((m) => {
      const on = state.prefs.family.includes(m);
      return el(
        "div",
        { className: "row" },
        el("label", { textContent: m === "maa" ? "Maa" : "Papa" }),
        switchEl(on, (checked) => {
          const f = new Set(state.prefs.family);
          if (checked) f.add(m);
          else if (f.size > 1) f.delete(m);
          state.prefs.family = [...f];
          save();
          renderFamily();
        })
      );
    })
  );
}

function renderReminders() {
  const rows = state.kinds
    .filter((k) => !k.calendar)
    .map((k) => {
      const cfg = state.prefs.reminders[k.id];
      const controls = el("div", { className: "controls" });

      if (cfg.enabled) {
        if (k.interval) {
          const sel = el("select", { title: "How often" });
          for (let m = 15; m <= 240; m += 15) sel.append(el("option", { value: m, textContent: `Every ${m} min` }));
          sel.value = cfg.intervalMinutes;
          sel.addEventListener("change", () => ((cfg.intervalMinutes = Number(sel.value)), save()));
          controls.append(sel);
        } else {
          const time = el("input", { type: "time", value: `${pad(cfg.hour)}:${pad(cfg.minute)}`, title: "At" });
          time.addEventListener("change", () => {
            const [h, m] = time.value.split(":").map(Number);
            if (Number.isFinite(h) && Number.isFinite(m)) {
              cfg.hour = h;
              cfg.minute = m;
              save();
            }
          });
          controls.append(time);
        }
        const owner = el("select", { title: "Asked by" });
        owner.append(el("option", { value: "maa", textContent: "Maa asks" }), el("option", { value: "papa", textContent: "Papa asks" }));
        owner.value = cfg.owner;
        owner.addEventListener("change", () => ((cfg.owner = owner.value), save()));
        controls.append(owner);
      }

      controls.append(
        switchEl(cfg.enabled, (on) => {
          cfg.enabled = on;
          save();
          renderReminders();
        })
      );
      return el("div", { className: "row" }, el("label", { textContent: k.title }), controls);
    });
  $("reminders").replaceChildren(...rows);
}

function renderCalendar() {
  const box = $("calendar");
  const cal = state.calendar;

  if (!cal.configured) {
    box.replaceChildren(el("div", { className: "row" }, el("p", { className: "muted", textContent: "Google Calendar sign-in isn't set up in this version yet." })));
    return;
  }

  if (!cal.connected) {
    const go = el("button", { className: "btn primary", textContent: "Connect Google Calendar" });
    go.addEventListener("click", async () => {
      go.disabled = true;
      go.textContent = "Waiting for Google…";
      toast("Finish signing in on the Google page that just opened in your browser.");
      const r = await gw.invoke("calendar:connect");
      state = r.state;
      toast(r.ok ? "Google Calendar connected. Maa will remind you before meetings." : r.message);
      render();
    });
    box.replaceChildren(
      el("div", { className: "row" }, el("label", {}, "Get a heads-up before meetings", el("br"), el("small", { className: "muted", textContent: cal.error || "Sign in with Google to connect your calendar." })), go)
    );
    return;
  }

  const cfg = state.prefs.reminders.meeting;
  const lead = el("select", { title: "Minutes before the meeting" });
  for (const m of [1, 2, 3, 5, 10, 15, 30]) lead.append(el("option", { value: m, textContent: `${m} min before` }));
  lead.value = cfg.intervalMinutes;
  lead.disabled = !cfg.enabled;
  lead.addEventListener("change", () => ((cfg.intervalMinutes = Number(lead.value)), save()));

  const off = el("button", { className: "btn", textContent: "Disconnect" });
  off.addEventListener("click", async () => {
    off.disabled = true;
    const r = await gw.invoke("calendar:disconnect");
    state = r.state;
    toast("Google Calendar disconnected.");
    render();
  });

  box.replaceChildren(
    el("div", { className: "row" }, el("label", { textContent: `Connected: ${cal.email || "Google Calendar"} ✓` }), off),
    el(
      "div",
      { className: "row" },
      el("label", { textContent: "Meeting heads-up" }),
      el("div", { className: "controls" }, lead, switchEl(cfg.enabled, (on) => ((cfg.enabled = on), save(), renderCalendar())))
    )
  );
}

function renderPro() {
  const box = $("pro");
  if (state.isPro) {
    const off = el("button", { className: "btn", textContent: "Deactivate on this computer" });
    off.addEventListener("click", async () => {
      await gw.invoke("license:deactivate");
      state.isPro = false;
      toast("Pro is off on this computer.");
      render();
    });
    box.replaceChildren(el("div", { className: "row" }, el("label", { textContent: "Status: Active ✓" }), off));
    return;
  }
  const input = el("input", { type: "text", placeholder: "License key (GHAR-XXXX-XXXX-XXXX)" });
  const go = el("button", { className: "btn primary", textContent: "Activate" });
  go.addEventListener("click", async () => {
    go.disabled = true;
    go.textContent = "Activating…";
    const r = await gw.invoke("license:activate", input.value);
    state.isPro = r.isPro;
    toast(r.message);
    render();
  });
  box.replaceChildren(
    el("div", { className: "row" }, el("p", { className: "muted", textContent: "Pro unlocks Strict tone now, and the rest of the family as they move in." })),
    el("div", { className: "row" }, el("div", { className: "controls grow" }, input, go))
  );
}

function bindSimple() {
  const p = state.prefs;
  const nick = $("nickname");
  nick.value = p.nickname;
  nick.oninput = () => ((p.nickname = nick.value), save());

  for (const id of ["language", "tone"]) {
    $(id).value = p[id];
    $(id).onchange = () => ((p[id] = $(id).value), save().then(render));
  }
  $("tone").options[1].textContent = state.isPro ? "Strict" : "Strict (Pro)";

  for (const id of ["showTranslation", "escalationEnabled", "launchAtLogin"]) {
    $(id).checked = p[id];
    $(id).onchange = () => ((p[id] = $(id).checked), save());
  }
  $("showTranslation").disabled = p.language === "english";
  $("launchLabel").textContent = state.platform === "win32" ? "Start Gharwale when Windows starts" : "Start Gharwale when you log in";

  for (const id of ["quietStartHour", "quietEndHour"]) {
    const sel = $(id);
    if (!sel.options.length) for (let h = 0; h < 24; h++) sel.append(el("option", { value: h, textContent: hourLabel(h) }));
    sel.value = p[id];
    sel.onchange = () => ((p[id] = Number(sel.value)), save());
  }

  for (const id of ["dailyCap", "snoozeMinutes"]) {
    $(id).value = p[id];
    $(id).onchange = () => ((p[id] = Number($(id).value)), save().then(() => ($(id).value = state.prefs[id])));
  }
}

function render() {
  bindSimple();
  renderFamily();
  renderReminders();
  renderCalendar();
  renderPro();
}

// Signed out elsewhere (e.g. access removed in the Google account): refresh the section.
gw.on("calendar:changed", async () => {
  state = await gw.invoke("state:get");
  renderCalendar();
});

gw.invoke("state:get").then((s) => {
  state = s;
  render();
});
