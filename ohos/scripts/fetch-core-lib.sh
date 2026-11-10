#!/usr/bin/env bash
# Fetch the prebuilt hiddify-core for OpenHarmony/HarmonyOS and drop it where the
# OHOS build packages it. The library is produced by `make ohos` in hiddify-core
# and published as hiddify-lib-ohos.tar.gz on the core release.
#
# Usage: ohos/scripts/fetch-core-lib.sh [tag]
#   tag  core release tag to pull from (default: v5.5.5)
#
# The result is git-ignored (ohos/.gitignore); it is a prebuilt native dependency,
# not source. Re-run this after changing the tag.

set -euo pipefail

tag="${1:-v5.5.5}"
repo="${CORE_REPO:-ShuttleSpace/hiddify-core}"
out_dir="$(cd "$(dirname "$0")/.." && pwd)/entry/libs/arm64-v8a"
url="https://github.com/${repo}/releases/download/${tag}/hiddify-lib-ohos.tar.gz"

mkdir -p "$out_dir"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $url"
curl -fSL "$url" -o "$tmp/hiddify-lib-ohos.tar.gz"

echo "Extracting lib/hiddify-core.so -> $out_dir/libhiddify-core.so"
tar -xzOf "$tmp/hiddify-lib-ohos.tar.gz" lib/hiddify-core.so > "$out_dir/libhiddify-core.so"

echo "Done: $(ls -lh "$out_dir/libhiddify-core.so" | awk '{print $5, $9}')"
