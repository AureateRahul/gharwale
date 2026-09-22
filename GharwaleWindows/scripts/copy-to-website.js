// After a build, puts the installers where the website's download buttons point.
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const { version } = require(path.join(root, "package.json"));
const downloads = path.join(root, "..", "downloads");

// built file in dist/  →  fixed name the website links to
const files = {
  [`Gharwale-Setup-${version}.exe`]: "Gharwale-Setup.exe",
  [`Gharwale-${version}.AppImage`]: "Gharwale.AppImage",
  [`gharwale_${version}_amd64.deb`]: "gharwale_amd64.deb",
};

fs.mkdirSync(downloads, { recursive: true });
let copied = 0;
for (const [built, target] of Object.entries(files)) {
  const from = path.join(root, "dist", built);
  if (!fs.existsSync(from)) continue;
  fs.copyFileSync(from, path.join(downloads, target));
  console.log(`Copied ${built} → downloads/${target}`);
  copied++;
}
if (!copied) {
  console.error("No installers found in dist/");
  process.exit(1);
}
