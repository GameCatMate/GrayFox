#!/bin/sh
set -eu
root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
toolchain="$root/.build/toolchain"
PATH="$toolchain/bin:$toolchain/python/bin:$toolchain/node_modules/.bin:$PATH"
export PATH

for tool in greadlink ninja esbuild node python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Missing build tool: %s\n' "$tool" >&2
        exit 1
    fi
done
xcrun metal --version >/dev/null
python3 -c 'import socks, httplib2'

checkout=$(sh "$root/Chromium/prepare.sh")
# Use the project toolchain without installing esbuild globally.
python3 - "$checkout/build.sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "/opt/homebrew/bin/esbuild --version"
new = "esbuild --version"
if old in text:
    if text.count(old) != 1:
        raise SystemExit("Unexpected number of esbuild paths in the upstream build")
    path.write_text(text.replace(old, new))
elif new not in text:
    raise SystemExit("Unexpected esbuild lookup in the upstream build")
PY

cd "$checkout"
MACOS_AD_HOC_SIGNING=1 bash build.sh arm64
app="$checkout/build/src/out/Default/Chromium.app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
