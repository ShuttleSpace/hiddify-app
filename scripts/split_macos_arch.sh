#!/usr/bin/env bash
# Split a universal Flutter macOS .app into per-arch zips (arm64 / x86_64).
#
# Usage: scripts/split_macos_arch.sh <Hiddify.app> <output-dir>
set -euo pipefail

APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT_DIR="${2:-dist}"

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

thin_and_zip() {
  local arch="$1"
  echo "==> Creating $arch package"

  local work
  work="$(mktemp -d)"
  local app="$work/Hiddify.app"
  ditto "$APP" "$app"

  # thin every universal Mach-O binary down to the requested arch
  while IFS= read -r f; do
    if lipo -info "$f" 2>/dev/null | grep -q "are:"; then
      lipo -thin "$arch" "$f" -o "$f.thin"
      mv "$f.thin" "$f"
    fi
  done < <(find "$app" -type f)

  # re-sign ad-hoc (thinning invalidates the original signature)
  codesign --force --deep --sign - "$app" >/dev/null 2>&1 || true

  local name="Hiddify-macOS-$arch"
  (cd "$work" && ditto -c -k --keepParent Hiddify.app "$OUT_DIR/$name.zip")
  echo "==> $OUT_DIR/$name.zip"
  rm -rf "$work"
}

thin_and_zip arm64
thin_and_zip x86_64

echo "Done."
