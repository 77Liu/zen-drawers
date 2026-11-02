#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-3.0.3}"
DIST="$PROJECT_DIR/dist"
BUILD="$PROJECT_DIR/work/native-build"
APP="$DIST/Zen 抽屉.app"
mkdir -p "$BUILD" "$DIST"
python3 - "$VERSION" <<'PY'
import re,sys
assert re.fullmatch(r'\d+\.\d+\.\d+',sys.argv[1]),'版本号应为 3.0.0 格式'
PY
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"
for ARCH in arm64 x86_64; do
 xcrun swiftc "$PROJECT_DIR/macOS/App.swift" "$PROJECT_DIR/macOS/LocalStore.swift" "$PROJECT_DIR/macOS/LocalServer.swift" -O -target "$ARCH-apple-macos13.1" -sdk "$(xcrun --sdk macosx --show-sdk-path)" -framework Cocoa -framework WebKit -framework Network -o "$BUILD/Zen-$ARCH"
done
lipo -create "$BUILD/Zen-arm64" "$BUILD/Zen-x86_64" -output "$APP/Contents/MacOS/ZenDrawers"
python3 - "$PROJECT_DIR" "$APP" "$VERSION" <<'PY'
import pathlib,plistlib,shutil,sys
root,app=map(pathlib.Path,sys.argv[1:3]);version=sys.argv[3]
web=app/'Contents/Resources/web'
if web.exists(): shutil.rmtree(web)
web.mkdir()
for name in ['Zen抽屉.html','manifest.webmanifest','zen-sw.js']: shutil.copy2(root/name,web/name)
shutil.copytree(root/'assets',web/'assets')
info=dict(CFBundleExecutable='ZenDrawers',CFBundleIdentifier='local.zen.drawers',CFBundleName='Zen 抽屉',CFBundleDisplayName='Zen 抽屉',CFBundleIconFile='Zen.icns',CFBundlePackageType='APPL',CFBundleShortVersionString=version,CFBundleVersion=version,LSMinimumSystemVersion='13.1',NSHighResolutionCapable=True,NSPrincipalClass='NSApplication',NSHumanReadableCopyright='Planning Zen / EasyMDE / DOMPurify licenses are retained in Resources/web.')
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
ICONSET="$BUILD/Zen.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
 sips -z "$SIZE" "$SIZE" "$PROJECT_DIR/Zen盆栽图标.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
 DOUBLE=$((SIZE*2))
 sips -z "$DOUBLE" "$DOUBLE" "$PROJECT_DIR/Zen盆栽图标.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Zen.icns"
if [[ -n "${ZEN_SIGN_IDENTITY:-}" ]]; then
 codesign --force --options runtime --timestamp --sign "$ZEN_SIGN_IDENTITY" "$APP"
else
 codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
STAGE="$BUILD/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Zen 抽屉.app"
ln -s /Applications "$STAGE/Applications"
cp "$PROJECT_DIR/macOS/安装说明.md" "$STAGE/安装说明.md"
DMG="$DIST/Zen抽屉-$VERSION-macOS-universal.dmg"
rm -f "$DMG"
hdiutil create -volname 'Zen 抽屉' -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
if [[ -n "${ZEN_NOTARY_PROFILE:-}" ]]; then
 : "${ZEN_SIGN_IDENTITY:?公证必须先设置 ZEN_SIGN_IDENTITY 为 Developer ID Application 证书}"
 xcrun notarytool submit "$DMG" --keychain-profile "$ZEN_NOTARY_PROFILE" --wait
 xcrun stapler staple "$DMG"
fi
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/Zen抽屉-$VERSION-macOS-universal.zip"
shasum -a 256 "$DMG" > "$DMG.sha256"
# Keep only compressed deliverables so Spotlight lists the installed app once.
rm -rf "$STAGE" "$APP" "$ICONSET"
printf '%s\n' "Built: $DMG" "Data remains in ~/.zen; no user records were packaged."
du -h "$DMG"

# This workstation's existing Dock entry points to this fixed installation.
# Set ZEN_INSTALL_LOCAL=0 for packaging only (e.g. CI or distribution builds).
if [[ "${ZEN_INSTALL_LOCAL:-1}" != "0" && -d "/Applications/Zen 抽屉.app" ]]; then
 bash "$PROJECT_DIR/macOS/install-local.sh" "$VERSION"
fi
