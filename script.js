// ---------- Hero: character peeks out of the notch with a reminder ----------
// who: picture in images/characters/ (your own Maa & Papa art)
const face = (name) => `images/characters/${name}.png`;
const reminders = [
  { who: "maa-neutral-1",  name: "Lunch time",   lang: "Hindi",     title: "Beta, khana kha lo. Thanda ho raha hai.", sub: "Your food is getting cold. Go eat." },
  { who: "papa-neutral-1", name: "Drink water",  lang: "Punjabi",   title: "Puttar, paani pee lai.",                 sub: "Have a glass of water, dear." },
  { who: "papa-stern-1",   name: "Stand up",     lang: "Hindi",     title: "Kab se baithe ho? Utho zara.",           sub: "You've been sitting too long. Stand up." },
  { who: "maa-worried-1",  name: "Rest eyes",    lang: "English",   title: "Eyes off the screen, please.",           sub: "Look far away for 20 seconds." },
  { who: "maa-happy-1",    name: "Call home",    lang: "Gujarati",  title: "Mummy ne phone karje, haan.",            sub: "Give your mom a call today." },
  { who: "maa-stern-1",    name: "Bedtime",      lang: "Marathi",   title: "Khup ushir jhala. Aata jhop.",           sub: "It's very late. Go to sleep now." },
  { who: "papa-happy-1",   name: "Breakfast",    lang: "Tamil",     title: "Tiffin saaptiya?",                       sub: "Did you have your breakfast?" },
  { who: "papa-stern-2",   name: "Sit straight", lang: "Bengali",   title: "Soja hoye bosho.",                       sub: "Fix your posture. Back straight." },
  { who: "maa-worried-1",  name: "Low battery",  lang: "Kannada",   title: "Charger haaku. Battery kadime aagide.",  sub: "Plug in your charger. Battery is low." },
  { who: "papa-neutral-2", name: "Short walk",   lang: "Telugu",    title: "Konchem nadavu, nanna.",                 sub: "Go for a short walk." },
  { who: "maa-neutral-2",  name: "Eat a fruit",  lang: "Hindi",     title: "Ek seb kha lo, bas.",                    sub: "Eat one fruit today." },
  { who: "maa-happy-2",    name: "Birthday",     lang: "English",   title: "Papa's birthday is tomorrow!",           sub: "Don't forget to wish him." },
  { who: "papa-happy-2",   name: "Tea break",    lang: "Malayalam", title: "Oru chaya kudikkam.",                    sub: "Take a small tea break." },
  { who: "papa-proud-1",   name: "Sunlight",     lang: "Hindi",     title: "Thodi dhoop le lo.",                     sub: "Step outside and get some sun." },
];

// Load all pictures early so they don't flash when the notch opens
reminders.forEach((r) => (new Image().src = face(r.who)));

const notch = document.getElementById("notch");
const avatar = document.getElementById("avatar");
const bubble = document.getElementById("bubble");
const bubbleTitle = document.getElementById("bubbleTitle");
const bubbleSub = document.getElementById("bubbleSub");
const player = document.querySelector(".player");
const countEl = document.getElementById("count");
const rName = document.getElementById("rName");
const rLang = document.getElementById("rLang");
const playBtn = document.getElementById("playBtn");
const nextBtn = document.getElementById("nextBtn");

const pad = (n) => String(n).padStart(2, "0");
let current = -1;
let playing = true;
let timer = null;
let swapTimer = null;
let closeTimer = null;

// Like iPhone Dynamic Island:
// 1) bubble tucks away → 2) notch shrinks up → 3) new content → 4) notch springs open
function goTo(index) {
  current = (index + reminders.length) % reminders.length;
  const item = reminders[current];
  const wasOpen = notch.classList.contains("open");

  bubble.classList.remove("show");
  player.classList.add("swap");

  clearTimeout(closeTimer);
  clearTimeout(swapTimer);
  closeTimer = setTimeout(() => notch.classList.remove("open"), wasOpen ? 180 : 0);
  swapTimer = setTimeout(() => {
    avatar.src = face(item.who);
    avatar.alt = item.who.startsWith("maa") ? "Maa" : "Papa";
    bubbleTitle.textContent = item.title;
    bubbleSub.textContent = item.sub;
    countEl.textContent = `${pad(current + 1)} / ${pad(reminders.length)}`;
    rName.textContent = item.name;
    rLang.textContent = item.lang;

    notch.classList.add("open");
    bubble.classList.add("show");
    player.classList.remove("swap");
    avatar.classList.remove("nod");
    void avatar.offsetWidth; // restart nod animation
    avatar.classList.add("nod");
  }, wasOpen ? 750 : 50); // wait for the close to finish before reopening
}

function schedule() {
  clearInterval(timer);
  if (playing) timer = setInterval(() => goTo(current + 1), 5000);
}

playBtn.addEventListener("click", () => {
  playing = !playing;
  playBtn.textContent = playing ? "❚❚" : "▶";
  playBtn.setAttribute("aria-label", playing ? "Pause" : "Play");
  schedule();
});

nextBtn.addEventListener("click", () => {
  goTo(current + 1);
  schedule(); // restart the 5s clock
});

setTimeout(() => {
  goTo(0);
  schedule();
}, 600);

// ---------- Voices: pick a face + language, phrase types itself ----------
// Same order as the tabs: English, Hindi, Tamil, Bengali, Gujarati, Marathi
const phrases = [
  "Did you eat something?",
  "Kuch khaya ki nahi?",
  "Ethavathu saapteengala?",
  "Kichu kheyecho?",
  "Kaink khadhu ke nahi?",
  "Kahi khalla ka?",
];
const phraseEl = document.getElementById("phrase");
const tabs = document.querySelectorAll(".tab");
const tabBar = document.getElementById("tabBar");
const faces = document.querySelectorAll(".face");
let typeTimer = null;
let langIndex = 0;

function typePhrase(text) {
  clearInterval(typeTimer);
  let n = 0;
  phraseEl.innerHTML = '<span></span><span class="caret"></span>';
  const out = phraseEl.firstChild;
  typeTimer = setInterval(() => {
    out.textContent = text.slice(0, ++n);
    if (n >= text.length) clearInterval(typeTimer);
  }, 45);
}

function moveBar(tab) {
  // White pill slides behind the active tab
  tabBar.style.width = `${tab.offsetWidth}px`;
  tabBar.style.height = `${tab.offsetHeight}px`;
  tabBar.style.transform = `translate(${tab.offsetLeft}px, ${tab.offsetTop}px)`;
}

function pickLang(i) {
  langIndex = i;
  tabs.forEach((t) => t.classList.toggle("active", Number(t.dataset.i) === i));
  moveBar(tabs[i]);
  typePhrase(phrases[i]);
}

tabs.forEach((tab) => tab.addEventListener("click", () => {
  pickLang(Number(tab.dataset.i));
  schedulePhrase();
}));

faces.forEach((btn) =>
  btn.addEventListener("click", () => {
    faces.forEach((f) => f.classList.remove("active"));
    btn.classList.add("active");
    typePhrase(phrases[langIndex]); // re-say the line in the new voice
  })
);

// Languages change by themselves every 3.5s; clicking a tab restarts the clock
let phraseClock = null;
function schedulePhrase() {
  clearInterval(phraseClock);
  phraseClock = setInterval(() => pickLang((langIndex + 1) % phrases.length), 3500);
}

tabBar.style.top = "0";
window.addEventListener("load", () => pickLang(0));
window.addEventListener("resize", () => moveBar(tabs[langIndex]));
schedulePhrase();

// ---------- Fade sections in on scroll ----------
const observer = new IntersectionObserver(
  (entries) =>
    entries.forEach((e) => {
      if (e.isIntersecting) {
        e.target.classList.add("show");
        observer.unobserve(e.target);
      }
    }),
  { threshold: 0.15 }
);
document.querySelectorAll(".section, .final").forEach((el) => {
  el.classList.add("reveal");
  observer.observe(el);
  // Give each child a number so they appear one after another
  el.querySelectorAll(".card, .steps li, .plan, .pill, .quote, .care-item").forEach((child, i) =>
    child.style.setProperty("--i", i)
  );
});

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

// ---------- Headline: wrap each word so it can drop in ----------
document.querySelectorAll(".split").forEach((el) => {
  let i = 0;
  const wrap = (node) => {
    [...node.childNodes].forEach((child) => {
      if (child.nodeType === Node.TEXT_NODE) {
        const frag = document.createDocumentFragment();
        child.textContent.split(/(\s+)/).forEach((part) => {
          if (!part) return;
          if (/^\s+$/.test(part)) return frag.append(part);
          const span = document.createElement("span");
          span.className = "w";
          span.style.setProperty("--i", i++);
          span.textContent = part;
          frag.append(span);
        });
        child.replaceWith(frag);
      } else if (child.nodeName !== "BR") {
        wrap(child);
      }
    });
  };
  wrap(el);
});

// ---------- Scroll progress bar + hide nav on scroll down ----------
const progress = document.getElementById("progress");
const nav = document.getElementById("nav");
let lastY = 0;
window.addEventListener(
  "scroll",
  () => {
    const y = window.scrollY;
    const max = document.documentElement.scrollHeight - window.innerHeight;
    progress.style.transform = `scaleX(${max > 0 ? y / max : 0})`;
    nav.classList.toggle("hide", y > lastY && y > 200);
    lastY = y;
  },
  { passive: true }
);

// ---------- Hero: floating stickers move slightly with the mouse ----------
const hero = document.querySelector(".hero");
const floaters = document.querySelectorAll(".floater");
if (!reduceMotion) {
  hero.addEventListener("mousemove", (e) => {
    const x = e.clientX / window.innerWidth - 0.5;
    const y = e.clientY / window.innerHeight - 0.5;
    floaters.forEach((f, i) => {
      const depth = (i % 3) + 1;
      f.style.marginLeft = `${x * depth * 20}px`;
      f.style.marginTop = `${y * depth * 20}px`;
    });
  });
}

// ---------- Reviews row scrolls by itself (pauses on hover) ----------
const carousel = document.getElementById("carousel");
let carouselPaused = false;
carousel.addEventListener("mouseenter", () => (carouselPaused = true));
carousel.addEventListener("mouseleave", () => (carouselPaused = false));
if (!reduceMotion) {
  setInterval(() => {
    if (carouselPaused) return;
    const atEnd = carousel.scrollLeft + carousel.clientWidth >= carousel.scrollWidth - 5;
    carousel.scrollTo({ left: atEnd ? 0 : carousel.scrollLeft + 336, behavior: "smooth" });
  }, 3000);
}

// ---------- Confetti when "Get Pro" is clicked ----------
const colors = ["#141414", "#717171", "#E5E7EB", "#B0B0B0"];
function confetti(x, y) {
  for (let i = 0; i < 60; i++) {
    const piece = document.createElement("span");
    piece.className = "confetti";
    piece.style.left = `${x}px`;
    piece.style.top = `${y}px`;
    piece.style.background = colors[i % colors.length];
    piece.style.setProperty("--dx", `${(Math.random() - 0.5) * 500}px`);
    piece.style.setProperty("--dy", `${Math.random() * 400 - 250}px`);
    piece.style.setProperty("--rot", `${Math.random() * 720}deg`);
    piece.style.setProperty("--t", `${0.9 + Math.random() * 0.8}s`);
    document.body.append(piece);
    setTimeout(() => piece.remove(), 1800);
  }
}
document.getElementById("getPro").addEventListener("click", (e) => {
  if (!reduceMotion) confetti(e.clientX, e.clientY);
});
