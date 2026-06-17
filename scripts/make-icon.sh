#!/usr/bin/env bash
# Generates AppIcon.icns — a macOS "squircle" app icon featuring the train glyph,
# matching the train theme of the overlay animation.
#
# The .icns is committed to Sources/AlertMe/Resources so day-to-day builds stay
# fast and deterministic; re-run this only when you want to change the artwork.
#
# Usage:
#   ./scripts/make-icon.sh
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_ICNS="Sources/AlertMe/Resources/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

MASTER="${WORK}/icon-1024.png"

echo "==> Rendering 1024px master with the train glyph…"
cat > "${WORK}/render.swift" <<'SWIFT'
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Rounded-rect ("squircle") background with a vertical gradient, inset slightly
// so the corners aren't clipped by the icon grid.
let inset: CGFloat = size * 0.06
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let corner = rect.width * 0.225
let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
path.addClip()

let top = NSColor(calibratedRed: 0.30, green: 0.58, blue: 0.98, alpha: 1.0)
let bottom = NSColor(calibratedRed: 0.13, green: 0.32, blue: 0.78, alpha: 1.0)
let gradient = NSGradient(starting: top, ending: bottom)!
gradient.draw(in: rect, angle: -90)

// White train glyph, centered, sized to ~60% of the canvas. A palette color
// configuration tints the symbol white directly, so we don't have to fight the
// template image's native rendering with blend modes.
let glyphTarget = size * 0.6
let sizeConfig = NSImage.SymbolConfiguration(pointSize: glyphTarget, weight: .regular)
let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
let config = sizeConfig.applying(colorConfig)
guard let symbol = NSImage(systemSymbolName: "train.side.front.car",
                           accessibilityDescription: "train")?
        .withSymbolConfiguration(config) else {
    fatalError("train symbol unavailable")
}

let glyphSize = symbol.size
let origin = NSPoint(x: (size - glyphSize.width) / 2,
                     y: (size - glyphSize.height) / 2)
let glyphRect = NSRect(origin: origin, size: glyphSize)
symbol.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1.0)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode PNG")
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

swift "${WORK}/render.swift" "${MASTER}"

echo "==> Building .iconset at all required sizes…"
ICONSET="${WORK}/AppIcon.iconset"
mkdir -p "${ICONSET}"
# name             size
sizes=(
  "icon_16x16.png 16"
  "icon_16x16@2x.png 32"
  "icon_32x32.png 32"
  "icon_32x32@2x.png 64"
  "icon_128x128.png 128"
  "icon_128x128@2x.png 256"
  "icon_256x256.png 256"
  "icon_256x256@2x.png 512"
  "icon_512x512.png 512"
  "icon_512x512@2x.png 1024"
)
for entry in "${sizes[@]}"; do
  name="${entry%% *}"
  px="${entry##* }"
  sips -z "${px}" "${px}" "${MASTER}" --out "${ICONSET}/${name}" >/dev/null
done

echo "==> Packing into ${OUT_ICNS}…"
iconutil -c icns "${ICONSET}" -o "${OUT_ICNS}"

echo "==> Done: ${OUT_ICNS}"
