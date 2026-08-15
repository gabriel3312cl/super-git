#!/bin/bash
# Compila SuperGit y arma el bundle dist/SuperGit.app
#
#   ./build.sh                  compila release para esta máquina
#   ./build.sh debug            compila debug
#   UNIVERSAL=1 ./build.sh      binario universal (arm64 + x86_64), para releases
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="SuperGit"
BUNDLE="dist/${APP_NAME}.app"

BUILD_ARGS=(-c "$CONFIG")
if [ "${UNIVERSAL:-0}" = "1" ]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "==> Compilando ($CONFIG${UNIVERSAL:+, universal})…"
swift build "${BUILD_ARGS[@]}"

BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/${APP_NAME}"

echo "==> Armando ${BUNDLE}…"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "$BIN_PATH" "${BUNDLE}/Contents/MacOS/${APP_NAME}"

if [ ! -f Resources/AppIcon.icns ]; then
    echo "==> Generando icono…"
    ./Resources/make-icon.sh
fi
cp Resources/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"

cat > "${BUNDLE}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>SuperGit</string>
    <key>CFBundleDisplayName</key>     <string>Super Git</string>
    <key>CFBundleExecutable</key>      <string>SuperGit</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleIdentifier</key>      <string>com.gserra.supergit</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Para descubrir repositorios git en tus carpetas.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Para descubrir repositorios git en tus carpetas.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Para descubrir repositorios git en tus carpetas.</string>
</dict>
</plist>
PLIST

# Firma ad-hoc: sin esto macOS trata la app como un binario suelto y los
# permisos de acceso a carpetas no se recuerdan entre ejecuciones.
codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || \
    echo "    (aviso: no se pudo firmar ad-hoc, la app igual corre)"

echo "==> Listo: ${BUNDLE}"
echo "    Abrir con:  open ${BUNDLE}"
