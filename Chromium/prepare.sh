#!/bin/sh
set -eu
root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
version=157.0.8103.78-1.1
checkout="$root/.build/ungoogled-chromium-macos-$version"

if [ ! -d "$checkout/.git" ]; then
    mkdir -p "$root/.build"
    git clone --branch "$version" --depth 1 --recurse-submodules --shallow-submodules \
        https://github.com/ungoogled-software/ungoogled-chromium-macos.git "$checkout"
fi
test "$(git -C "$checkout" rev-parse HEAD)" = \
     "$(git -C "$checkout" rev-parse "refs/tags/$version^{commit}")"

series="$checkout/patches/series"
for name in group-ribbon app-name group-picker; do
    patch="ungoogled-chromium/macos/mybro-$name.patch"
    cp "$root/Chromium/$name.patch" "$checkout/patches/$patch"
    if ! grep -qxF "$patch" "$series"; then
        printf '%s\n' "$patch" >> "$series"
    fi
done

printf '%s\n' "$checkout"
