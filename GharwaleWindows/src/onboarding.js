// First-run welcome: 3 steps (family → voice → check-ins), then Maa says good morning.
const $ = (id) => document.getElementById(id);
let state;
let step = 0;

const el = (tag, props = {}, ...children) => {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children);
  return node;
};

const pad = (n) => String(n).padStart(2, "0");
const loginLabel = () => (state.platform === "win32" ? "Start Gharwale when Windows starts" : "Start Gharwale when you log in");

function switchEl(checked, onChange, label) {
  const input = el("input", { type: "checkbox", checked });
  if (label) input.setAttribute("aria-label", label);
  input.addEventListener("change", () => onChange(input.checked));
  return el("span", { className: "switch" }, input, el("span"));
}

function setFaces() {
  const f = state.faces;
  $("faceMaa").src = step === 2 ? f.maaProud : f.maaHappy;
  $("facePapa").src = step === 1 ? f.papaStern : f.papaNeutral;
  for (const id of ["faceMaa", "facePapa"]) {
    $(id).classList.remove("bob");
    void $(id).offsetWidth;
    $(id).classList.add("bob");
  }
}

// ---------- Step 1: family ----------

function stepFamily() {
  const p = state.prefs;
  const nick = el("input", { type: "text", className: "field", id: "nick", value: p.nickname, placeholder: "beta, Munna, Chinku…", maxLength: 30 });
  nick.addEventListener("input", () => (p.nickname = nick.value));

  const members = ["maa", "papa"].map((m) => {
    const name = m === "maa" ? "Maa" : "Papa";
    return el(
      "div",
      { className: "check" },
      el("span", { className: "name" }, name, el("small", { textContent: m === "maa" ? "Meals, water and good morning" : "Moving around and bedtime" })),
      switchEl(p.family.includes(m), (on) => {
        const f = new Set(p.family);
        if (on) f.add(m);
        else if (f.size > 1) f.delete(m);
        p.family = [...f];
        render(); // re-draw so the last parent can't be switched off
      }, name)
    );
  });

  return [
    el("h1", { textContent: "Meet your family" }),
    el("p", { className: "lead", textContent: "They'll drop down from the top of your screen to make sure you eat, drink water, move and sleep." }),
    el("div", {}, el("label", { className: "field-label", htmlFor: "nick", textContent: "What do they call you?" }), nick),
    el("div", { className: "card" }, ...members),
  ];
}

// ---------- Step 2: voice ----------

function stepVoice() {
  const p = state.prefs;
  const seg = el("div", { className: "seg wide", role: "radiogroup" });
  for (const [val, label] of [["hinglish", "Hinglish"], ["english", "English"]]) {
    const b = el("button", { textContent: label, className: p.language === val ? "on" : "" });
    b.setAttribute("role", "radio");
    b.setAttribute("aria-checked", String(p.language === val));
    b.addEventListener("click", () => ((p.language = val), render()));
    seg.append(b);
  }

  const sample = p.language === "english" ? "Have you eaten, beta?" : "Khana khaya, beta?";
  const trans = el(
    "div",
    { className: `check${p.language === "english" ? " off" : ""}` },
    el("span", { className: "name" }, "Show the English line underneath", el("small", { textContent: "Handy while you get used to Hinglish" })),
    el("span", { className: "ctl" }, switchEl(p.showTranslation, (on) => (p.showTranslation = on), "Show the English line underneath"))
  );

  return [
    el("h1", { textContent: "How do they talk?" }),
    el("p", { className: "lead", textContent: `For example: "${sample}"` }),
    seg,
    el("div", { className: "card" }, trans),
    el("p", { className: "muted small", textContent: "Soft tone is included. Strict tone comes with Pro, and you can switch any time in Settings." }),
  ];
}

// ---------- Step 3: check-ins, with times you can change ----------

function timeControl(k, c) {
  if (k.interval) {
    const sel = el("select", { title: `How often: ${k.title}` });
    for (const m of [30, 45, 60, 75, 90, 120, 150, 180]) sel.append(el("option", { value: m, textContent: `Every ${m} min` }));
    if (![...sel.options].some((o) => Number(o.value) === c.intervalMinutes)) {
      sel.append(el("option", { value: c.intervalMinutes, textContent: `Every ${c.intervalMinutes} min` }));
    }
    sel.value = c.intervalMinutes;
    sel.addEventListener("change", () => (c.intervalMinutes = Number(sel.value)));
    return sel;
  }
  const time = el("input", { type: "time", value: `${pad(c.hour)}:${pad(c.minute)}`, title: `Time: ${k.title}` });
  time.addEventListener("change", () => {
    const [h, m] = time.value.split(":").map(Number);
    if (Number.isFinite(h) && Number.isFinite(m)) {
      c.hour = h;
      c.minute = m;
    }
  });
  return time;
}

function stepRhythm() {
  const p = state.prefs;
  const rows = state.kinds
    .filter((k) => !k.calendar)
    .map((k) => {
      const c = p.reminders[k.id];
      const who = c.owner === "papa" ? "Papa" : "Maa";
      const row = el(
        "div",
        { className: `check${c.enabled ? "" : " off"}` },
        el("span", { className: "name" }, k.title, el("small", { textContent: `${who} asks` })),
        el("span", { className: "ctl" }, timeControl(k, c)),
        switchEl(c.enabled, (on) => {
          c.enabled = on;
          row.classList.toggle("off", !on);
        }, k.title)
      );
      return row;
    });

  const login = el(
    "div",
    { className: "check" },
    el("span", { className: "name" }, loginLabel(), el("small", { textContent: "So they're always around" })),
    switchEl(p.launchAtLogin, (on) => (p.launchAtLogin = on), loginLabel())
  );

  return [
    el("h1", { textContent: "Pick your check-ins" }),
    el("p", { className: "lead", textContent: "Click a time to change it. You can switch any check-in off." }),
    el("div", { className: "card" }, ...rows),
    el("div", { className: "card" }, login),
  ];
}

// ---------- Navigation ----------

function render() {
  const view = [stepFamily, stepVoice, stepRhythm][step]();
  $("step").replaceChildren(...view);
  $("step").scrollTop = 0;
  $("back").style.visibility = step === 0 ? "hidden" : "visible";
  $("next").textContent = step === 2 ? "Bring them home" : "Next";
  [...$("dots").children].forEach((d, i) => d.classList.toggle("on", i === step));
  $("dots").setAttribute("aria-label", `Step ${step + 1} of 3`);
}

function go(to) {
  step = to;
  setFaces();
  render();
}

$("back").addEventListener("click", () => step > 0 && go(step - 1));

$("next").addEventListener("click", async () => {
  if (step < 2) return go(step + 1);
  $("next").disabled = true;
  $("next").textContent = "Bringing them home…";
  await gw.invoke("onboarding:finish", state.prefs);
});

document.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && e.target.tagName === "INPUT" && e.target.type === "text") $("next").click();
});

gw.invoke("state:get").then((s) => {
  state = s;
  setFaces();
  render();
});
