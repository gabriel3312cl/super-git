#!/bin/bash
# Genera Resources/AppIcon.icns a partir de AppIcon.svg
#
# Se rasteriza el SVG una vez a 1024 con QuickLook y se reescala con sips:
# el icono usa desenfoques, así que reducir desde 1024 da mejor resultado
# que rasterizar cada tamaño por separado.
set -euo pipefail

cd "$(dirname "$0")"

SVG="AppIcon.svg"
ICONSET="AppIcon.iconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v qlmanage >/dev/null || { echo "qlmanage no disponible"; exit 1; }

echo "==> Rasterizando ${SVG} a 1024×1024…"
qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null 2>&1
MASTER="$TMP/${SVG}.png"
[ -f "$MASTER" ] || { echo "QuickLook no pudo renderizar el SVG"; exit 1; }

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

emit() { # emit <tamaño-px> <nombre>
    sips -z "$1" "$1" "$MASTER" --out "${ICONSET}/$2" >/dev/null
}

emit 16   icon_16x16.png
emit 32   icon_16x16@2x.png
emit 32   icon_32x32.png
emit 64   icon_32x32@2x.png
emit 128  icon_128x128.png
emit 256  icon_128x128@2x.png
emit 256  icon_256x256.png
emit 512  icon_256x256@2x.png
emit 512  icon_512x512.png
cp "$MASTER" "${ICONSET}/icon_512x512@2x.png"

echo "==> Empaquetando AppIcon.icns…"
iconutil -c icns "$ICONSET" -o AppIcon.icns
rm -rf "$ICONSET"

echo "==> Listo: Resources/AppIcon.icns"
