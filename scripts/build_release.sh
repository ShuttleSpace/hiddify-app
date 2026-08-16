#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/hiddify-core"
ANDROID_LIBS_DIR="$ROOT_DIR/android/app/libs"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"

PURO_BIN="${PURO_BIN:-$(command -v puro || true)}"
if [[ -z "$PURO_BIN" && -x "$HOME/.puro/bin/puro" ]]; then
  PURO_BIN="$HOME/.puro/bin/puro"
fi

if [[ -z "$PURO_BIN" ]]; then
  echo "puro not found. Set PURO_BIN or install puro." >&2
  exit 1
fi

PLATFORM=""
ARCH="auto"

usage() {
  cat <<'EOF'
Usage:
  scripts/build_release.sh --platform <macos|android> [--arch <arch>]

macOS arches:
  auto | arm64 | x86_64 | amd64

Android arches:
  auto | arm | arm64 | x86 | x86_64 | amd64 | 386

Examples:
  scripts/build_release.sh --platform macos --arch arm64
  scripts/build_release.sh --platform android --arch arm64
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      PLATFORM="${2:-}"
      shift 2
      ;;
    --arch)
      ARCH="${2:-auto}"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="${2:-$ROOT_DIR/dist}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$PLATFORM" ]]; then
  echo "--platform is required" >&2
  usage
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

build_macos() {
  local requested_arch="$1"
  local host_arch
  host_arch="$(uname -m)"

  case "$host_arch" in
    arm64) host_arch="arm64" ;;
    x86_64) host_arch="x86_64" ;;
    amd64) host_arch="x86_64" ;;
  esac

  if [[ "$requested_arch" == "auto" ]]; then
    requested_arch="$host_arch"
  fi

  local core_arch
  local app_arch
  case "$requested_arch" in
    arm64)
      core_arch="arm64"
      app_arch="arm64"
      ;;
    x86_64|amd64)
      core_arch="amd64"
      app_arch="x86_64"
      ;;
    *)
      echo "Unsupported macOS arch: $requested_arch" >&2
      exit 1
      ;;
  esac

  echo "==> Building hiddify-core for macOS/$app_arch"
  make -C "$CORE_DIR" "macos-$core_arch"

  local core_dylib="$CORE_DIR/bin/hiddify-core-$core_arch.dylib"
  local linked_dylib="$CORE_DIR/bin/hiddify-core.dylib"
  echo "==> Linking core dylib: $core_dylib"
  cp "$core_dylib" "$linked_dylib"

  echo "==> Building Flutter macOS app"
  "$PURO_BIN" flutter build macos --release \
    --tree-shake-icons \
    --split-debug-info="$ROOT_DIR/build/symbols/macos-$app_arch"

  local app_src="$ROOT_DIR/build/macos/Build/Products/Release/Hiddify.app"
  local app_dst="$OUTPUT_DIR/Hiddify-$app_arch.app"
  echo "==> Exporting $app_dst"
  rm -rf "$app_dst"
  cp -R "$app_src" "$app_dst"
}

build_android() {
  local requested_arch="$1"

  if [[ "$requested_arch" == "auto" ]]; then
    requested_arch="arm64"
  fi

  local core_arch
  local flutter_target
  local app_arch
  case "$requested_arch" in
    arm)
      core_arch="arm"
      flutter_target="android-arm"
      app_arch="armeabi-v7a"
      ;;
    arm64)
      core_arch="arm64"
      flutter_target="android-arm64"
      app_arch="arm64-v8a"
      ;;
    x86|386)
      core_arch="386"
      flutter_target="android-x86"
      app_arch="x86"
      ;;
    x86_64|amd64)
      core_arch="amd64"
      flutter_target="android-x64"
      app_arch="x86_64"
      ;;
    *)
      echo "Unsupported Android arch: $requested_arch" >&2
      exit 1
      ;;
  esac

  echo "==> Building hiddify-core for Android/$app_arch"
  make -C "$CORE_DIR" "android-$core_arch"

  local core_aar="$CORE_DIR/bin/hiddify-core-$core_arch.aar"
  local linked_aar="$ANDROID_LIBS_DIR/hiddify-core.aar"
  mkdir -p "$ANDROID_LIBS_DIR"
  echo "==> Linking core AAR: $core_aar"
  cp "$core_aar" "$linked_aar"

  echo "==> Building Flutter Android APK for $flutter_target"
  "$PURO_BIN" flutter build apk --release \
    --target-platform "$flutter_target" \
    --tree-shake-icons \
    --split-debug-info="$ROOT_DIR/build/symbols/android-$app_arch"

  local apk_src="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
  local apk_dst="$OUTPUT_DIR/Hiddify-$app_arch-release.apk"
  echo "==> Exporting $apk_dst"
  cp "$apk_src" "$apk_dst"
}

case "$PLATFORM" in
  macos)
    build_macos "$ARCH"
    ;;
  android)
    build_android "$ARCH"
    ;;
  *)
    echo "Unsupported platform: $PLATFORM" >&2
    usage
    exit 1
    ;;
esac

echo "Done. Output directory: $OUTPUT_DIR"
