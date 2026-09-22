// Copies the shared character art and reminder lines from the Mac app,
// so both apps always show the same faces and say the same things.
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const mac = path.join(root, "..", "Gharwale");

function copyDir(from, to, ext) {
  if (!fs.existsSync(from)) {
    console.log(`skip: ${from} not found (keeping existing ${path.basename(to)})`);
    return;
  }
  fs.mkdirSync(to, { recursive: true });
  const files = fs.readdirSync(from).filter((f) => f.endsWith(ext));
  for (const f of files) fs.copyFileSync(path.join(from, f), path.join(to, f));
  console.log(`synced ${files.length} ${ext} files → ${path.relative(root, to)}`);
}

copyDir(path.join(mac, "Characters"), path.join(root, "assets", "Characters"), ".png");
copyDir(path.join(mac, "ContentPacks"), path.join(root, "assets", "ContentPacks"), ".json");

// App icon (Windows needs at least 256×256)
const icon = path.join(root, "assets", "Characters", "maa-happy-1.png");
if (fs.existsSync(icon)) {
  fs.mkdirSync(path.join(root, "build"), { recursive: true });
  fs.copyFileSync(icon, path.join(root, "build", "icon.png"));
}
