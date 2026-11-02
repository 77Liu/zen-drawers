#!/bin/bash
# Update the fixed App path so existing Dock and Finder shortcuts keep working.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-3.0.4}"
TARGET="/Applications/Zen 抽屉.app"
ARCHIVE="$PROJECT_DIR/dist/Zen抽屉-$VERSION-macOS-universal.zip"
if pgrep -x ZenDrawers >/dev/null; then
  echo '请先正常退出 Zen 抽屉，再执行安装；已有记录保留在 ~/.zen。' >&2
  exit 1
fi
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/zen-install.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto -x -k "$ARCHIVE" "$STAGING"
SOURCE="$STAGING/Zen 抽屉.app"
codesign --verify --strict "$SOURCE"
python3 - "$SOURCE" "$VERSION" "$TARGET" <<'PY'
import pathlib,plistlib,shutil,sys
source=pathlib.Path(sys.argv[1]);version=sys.argv[2];target=pathlib.Path(sys.argv[3])
info=plistlib.loads((source/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='local.zen.drawers'
assert info['CFBundleShortVersionString']==version
# Keep the bundle directory inode: Dock bookmarks continue to resolve to this App.
target.mkdir(exist_ok=True)
contents=target/'Contents'
if contents.exists(): shutil.rmtree(contents)
shutil.copytree(source/'Contents',contents,copy_function=shutil.copy2)
print(f'Installed {version}: {target}; user data remains in ~/.zen')
PY
codesign --verify --strict "$TARGET"
