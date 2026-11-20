#!/bin/sh
set -eu
root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
app="${MYBRO_CHROMIUM_APP:-$root/.build/Chromium.app}"

if [ ! -x "$app/Contents/MacOS/Chromium" ]; then
    printf '%s\n' "Chromium.app is missing. See Chromium/README.md." >&2
    exit 1
fi

exec open -na "$app" --args \
    "--user-data-dir=$root/.build/mybro-chromium-profile" \
    --no-first-run \
    --enable-features=TabGroupsFocusing,NonGroupFocus \
    --disable-features=VerticalTabs,TabGroupRibbon "$@"
