// Draws the tab + bubble and runs the open/close animation. The app decides what to say.
const $ = (id) => document.getElementById(id);
const faces = $("faces");
const bubble = $("bubble");
const lines = $("lines");
const buttons = $("buttons");
const body = document.body;

let timers = [];
let speakers = [];
let primary = null;

const later = (ms, fn) => timers.push(setTimeout(fn, ms));
const clearTimers = () => {
  timers.forEach(clearTimeout);
  timers = [];
};

const PANEL_W = 820;
const tabWidth = () => (speakers.length > 1 ? 306 : 196);

function setTabWidth() {
  document.documentElement.style.setProperty("--tab-w", `${tabWidth()}px`);
  sendShape();
}

// Linux only (ignored on Windows): tell the app where the tab and bubble are,
// so the window is cut to just those areas and clicks elsewhere reach your apps.
function sendShape() {
  requestAnimationFrame(() => {
    const w = tabWidth();
    const pad = 18; // room for shadows and the springy overshoot
    const tab = { x: PANEL_W / 2 - w / 2 - pad, y: 0, width: w + pad * 2, height: 132 + pad };
    const left = PANEL_W / 2 + w / 2 - 46 - 20; // bubble's tail sticks out 20px
    const bub = { x: left - pad, y: 44 - pad, width: 320 + pad * 2, height: bubble.offsetHeight + pad * 2 };
    gw.send("overlay:shape", [tab, bub]);
  });
}

function faceEl(u) {
  const img = document.createElement("img");
  img.className = "face";
  img.alt = `${u.name}, ${u.mood}`;
  img.dataset.who = u.character;
  if (u.image) img.src = u.image;
  return img;
}

function lineEl(u, showName) {
  const el = document.createElement("div");
  el.className = "line";
  if (showName) el.append(Object.assign(document.createElement("div"), { className: "who", textContent: u.name }));
  el.append(Object.assign(document.createElement("div"), { className: "text", textContent: u.text }));
  if (u.subtitle) el.append(Object.assign(document.createElement("div"), { className: "sub", textContent: u.subtitle }));
  return el;
}

function renderButtons(list) {
  buttons.replaceChildren(
    ...list.map((b) => {
      const btn = document.createElement("button");
      btn.className = b.primary ? "btn primary" : "btn";
      btn.textContent = b.title;
      btn.addEventListener("click", () => gw.send("overlay:button", b.id));
      return btn;
    })
  );
}

/** Replace everything with one speaker (new reminder, or a reaction). */
function showSingle(u, buttonList) {
  primary = u;
  speakers = [u.character];
  faces.replaceChildren(faceEl(u));
  lines.replaceChildren(lineEl(u, false));
  renderButtons(buttonList);
  setTabWidth();
}

// New reminder: tab springs down, then the bubble pops out beside it.
gw.on("show", (d) => {
  clearTimers();
  body.classList.remove("expanded", "bubble-on");
  showSingle(d.primary, d.buttons);
  void faces.offsetWidth; // restart the animation
  later(40, () => {
    body.classList.add("expanded");
    later(240, () => body.classList.add("bubble-on"));
  });
});

// Tag-team: the other parent slides in and adds a line.
gw.on("secondary", (u) => {
  if (!speakers.includes(u.character)) {
    speakers.push(u.character);
    const img = faceEl(u);
    img.classList.add("enter");
    faces.append(img);
    requestAnimationFrame(() => requestAnimationFrame(() => img.classList.remove("enter")));
  }
  setTabWidth();
  if (primary) lines.firstChild.replaceWith(lineEl(primary, true));
  const l = lineEl(u, true);
  l.classList.add("enter");
  lines.append(l);
  sendShape(); // bubble got taller
  requestAnimationFrame(() => requestAnimationFrame(() => l.classList.remove("enter")));
});

// Reaction after "Theek hai": swap the line, no buttons.
gw.on("react", (u) => {
  clearTimers();
  showSingle(u, []);
  body.classList.add("expanded", "bubble-on");
});

// Bubble tucks away first, then the tab shrinks back up.
gw.on("hide", () => {
  clearTimers();
  body.classList.remove("bubble-on");
  gw.send("overlay:interactive", false);
  later(150, () => body.classList.remove("expanded"));
});

// Clicks only land on the bubble; everywhere else they pass through to your apps.
bubble.addEventListener("mouseenter", () => gw.send("overlay:interactive", true));
bubble.addEventListener("mouseleave", () => gw.send("overlay:interactive", false));
