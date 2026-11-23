#!/usr/bin/env node
/**
 * Generate every Flutter app icon and splash asset from one inline SVG source.
 *
 *   node scripts/generate-flutter-icons.mjs
 *
 * The TWRXA mark is shared across Android adaptive icons, iOS AppIcon sets,
 * web PWA icons, and native splash screens.
 *
 * Outputs:
 *   assets/icon/    1024px icon + adaptive foreground/background layers
 *   assets/splash/  light and dark splash canvases
 *   web/icons/      PWA icons
 *   web/favicon.png
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import sharp from "sharp";

const ROOT = process.cwd();

const BG = "#080B09";
const ACID = "#39FF14";
const PINK = "#FF2D95";
const VIOLET = "#B026FF";

const markPaths = `
  <path d="M92 124h328v70H300v194h-82V194H92z" fill="${ACID}"/>
  <path d="m308 262 36-36 88 88-36 36zM396 226l36 36-88 88-36-36z" fill="${PINK}"/>
  <path d="M92 412h328" fill="none" stroke="${VIOLET}" stroke-width="14" stroke-linecap="round"/>`;

function twrxaMark({ size, withPlate }) {
  const plate = withPlate
    ? `<rect width="512" height="512" rx="112" fill="${BG}"/>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 512 512">
  ${plate}
  ${markPaths}
</svg>`;
}

/** Full-bleed splash canvas with the mark centred. */
function splash({ size }) {
  const background = BG;
  const markSize = size * 0.6;
  const offset = (size - markSize) / 2;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <rect width="${size}" height="${size}" fill="${background}"/>
  <g transform="translate(${offset} ${offset}) scale(${markSize / 512})">${markPaths}</g>
</svg>`;
}

const svgFavicon = twrxaMark({ size: 64, withPlate: true });

async function png(svg, outPath, size) {
  const buf = await sharp(Buffer.from(svg)).resize(size, size).png().toBuffer();
  const target = join(ROOT, outPath);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, buf);
  console.log(`[icons] ${outPath} (${buf.length} bytes)`);
}

// --- icon + adaptive layers, consumed by flutter_launcher_icons ---
await png(twrxaMark({ size: 1024, withPlate: true }), "assets/icon/icon.png", 1024);
await png(twrxaMark({ size: 1024, withPlate: false }), "assets/icon/icon-foreground.png", 1024);
await png(
  `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"><rect width="1024" height="1024" fill="${BG}"/></svg>`,
  "assets/icon/icon-background.png",
  1024,
);

// --- splash, consumed by flutter_native_splash ---
await png(splash({ size: 1024 }), "assets/splash/splash-dark.png", 1024);
await png(splash({ size: 1024 }), "assets/splash/splash.png", 1024);

// --- web PWA + favicon ---
await png(twrxaMark({ size: 512, withPlate: true }), "web/icons/Icon-512.png", 512);
await png(twrxaMark({ size: 256, withPlate: true }), "web/icons/Icon-192.png", 192);
await png(twrxaMark({ size: 256, withPlate: true }), "web/favicon.png", 64);

// The maskable variant keeps the mark inside the safe circle Android and iOS
// crop to when a PWA is pinned to a home screen.
await png(twrxaMark({ size: 512, withPlate: false }), "web/icons/Icon-maskable-512.png", 512);

const svgTarget = join(ROOT, "web/icons/twrxa-mark.svg");
mkdirSync(dirname(svgTarget), { recursive: true });
writeFileSync(svgTarget, svgFavicon);
console.log("[icons] web/icons/twrxa-mark.svg");

console.log("\n[icons] done.");
console.log("Next:");
console.log("  dart run flutter_launcher_icons   # Android + iOS app icons");
console.log("  dart run flutter_native_splash    # Android + iOS splash screens");