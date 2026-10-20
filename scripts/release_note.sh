#!/usr/bin/env bash
# 生成 fork 的 release note：下载表 + 版本 + 提交 + 本次改动。
#
# 上游的 .github/release_message.md 是一张写死了上游仓库地址的表，fork 用它会
# 把下载链接指到 hiddify/hiddify-app 上去；而且它靠 gitchangelog 对着上游的
# 历史生成变更列表，fork 的历史跟它不是一回事。这里按实际产物生成，链接指到
# 本仓库，变更列表取上一个 release 之后的提交。
#
# 用法: scripts/release_note.sh <out_dir> <tag> <owner/repo> <sha> <channel>
# 结果写到 stdout。

set -uo pipefail

out_dir="${1:-out}"
tag="${2:-draft}"
repo="${3:-hiddify/hiddify-app}"
sha="${4:-}"
channel="${5:-dev}"

repo_url="https://github.com/${repo}"
download_base="${repo_url}/releases/download/${tag}"

# --- 版本 -------------------------------------------------------------------
version_line="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml 2>/dev/null | head -1)"
version_name="${version_line%%+*}"
version_code="${version_line##*+}"
[ -n "$version_name" ] || version_name="unknown"

# --- 提交 -------------------------------------------------------------------
commit_subject=""
if [ -n "$sha" ] && git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null 2>&1; then
  commit_subject="$(git log -1 --format=%s "$sha")"
fi

# --- 产物表 -----------------------------------------------------------------
# 文件名到平台说明的映射。没列到的文件按原名列出，不会被丢掉。
describe() {
  case "$1" in
    Hiddify-Android-universal.apk) echo "Android · 通用版" ;;
    Hiddify-Android-arm64.apk) echo "Android · ARMv8 (64 位)" ;;
    Hiddify-Android-arm7.apk) echo "Android · ARMv7" ;;
    Hiddify-Android-x86_64.apk) echo "Android · x86_64" ;;
    Hiddify-Debian-x64.deb) echo "Debian · x64" ;;
    Hiddify-Linux-x64-AppImage.AppImage) echo "Linux · x64 (AppImage)" ;;
    Hiddify-Linux-x64-AppImage.tar.gz) echo "Linux · x64 (AppImage 压缩包)" ;;
    Hiddify-MacOS.dmg) echo "macOS · 通用版 (DMG)" ;;
    Hiddify-MacOS-Installer.pkg) echo "macOS · 安装包 (PKG)" ;;
    Hiddify-Windows-Portable-x64.zip) echo "Windows · 便携版 (ZIP)" ;;
    Hiddify-Windows-Setup-x64.exe) echo "Windows · 安装版 (EXE)" ;;
    *) echo "$1" ;;
  esac
}

size_of() {
  local bytes
  bytes="$(wc -c < "$1" 2>/dev/null | tr -d ' ')"
  [ -n "$bytes" ] || { echo "-"; return; }
  awk -v b="$bytes" 'BEGIN { printf "%d MB", b / 1048576 }'
}

echo "# Hiddify ${version_name} (${version_code}) · ${channel}"
echo
if [ -n "$sha" ]; then
  short="${sha:0:8}"
  if [ -n "$commit_subject" ]; then
    echo "构建自 [\`${short}\`](${repo_url}/commit/${sha}) — ${commit_subject}"
  else
    echo "构建自 [\`${short}\`](${repo_url}/commit/${sha})"
  fi
  echo
  echo "生成于 $(date -u '+%Y-%m-%d %H:%M UTC')。"
fi
echo
echo "## 下载"
echo
echo "| 平台 | 文件 | 大小 |"
echo "|---|---|---|"

found=0
if [ -d "$out_dir" ]; then
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    name="$(basename "$file")"
    found=1
    echo "| $(describe "$name") | [\`${name}\`](${download_base}/${name}) | $(size_of "$file") |"
  done < <(find "$out_dir" -maxdepth 1 -type f | sort)
fi
if [ "$found" -eq 0 ]; then
  echo "| — | *没有产物* | — |"
fi

echo
echo "## 本次改动"
echo
# 上一个同名的 release 的提交作为起点；没有就退回最近 30 个提交。
previous=""
if git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null 2>&1; then
  previous="$(git rev-parse "refs/tags/${tag}")"
fi

listed=0
if [ -n "$previous" ] && [ -n "$sha" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    listed=$((listed + 1))
    echo "- $line"
  done < <(git log --no-merges --format='`%h` %s' "${previous}..${sha}" 2>/dev/null | head -30)
fi
if [ "$listed" -eq 0 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    listed=$((listed + 1))
    echo "- $line"
  done < <(git log --no-merges -30 --format='`%h` %s' 2>/dev/null)
fi
if [ "$listed" -eq 0 ]; then
  echo "- *没有可列出的提交*"
fi

echo
if [ -n "$previous" ] && [ -n "$sha" ]; then
  echo "完整对比：[${previous:0:8}…${sha:0:8}](${repo_url}/compare/${previous}...${sha})"
else
  echo "完整历史：[${repo_url}/commits/${channel}](${repo_url}/commits/${channel})"
fi
