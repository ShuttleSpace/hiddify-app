#!/usr/bin/env bash
# 生成 fork 的 release note：下载表 + 版本 + 提交 + 本次改动。
#
# 上游的 .github/release_message.md 是一张写死了上游仓库地址的表，fork 用它会
# 把下载链接指到 hiddify/hiddify-app 上去；而且它靠 gitchangelog 对着上游的
# 历史生成变更列表，fork 的历史跟它不是一回事。这里按实际产物生成，链接指到
# 本仓库，变更列表取上一个 release 之后的提交。
#
# 用法: scripts/release_note.sh <out_dir> <tag> <owner/repo> <sha> <channel> [existing_assets_tsv]
# 结果写到 stdout。
#
# 第 6 个可选参数是一个 TSV（name<TAB>size_bytes），列出现有 release 里已经存在、
# 但本轮没有重新产出的资产。把它并入下载表，避免“描述里漏了 assets 里有的平台”
# 的情况——典型是某个平台腿本轮被跳过/取消（如 macOS arm64 runner 容量），而该产物
# 仍残留在 release 里。

set -uo pipefail

out_dir="${1:-out}"
tag="${2:-draft}"
repo="${3:-hiddify/hiddify-app}"
sha="${4:-}"
channel="${5:-dev}"
existing_assets_file="${6:-}"

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
    hiddifyctl-linux-amd64) echo "hiddifyctl · Linux x64 (CLI)" ;;
    hiddifyctl-linux-arm64) echo "hiddifyctl · Linux ARM64 (CLI)" ;;
    hiddifyctl-darwin-amd64) echo "hiddifyctl · macOS Intel (CLI)" ;;
    hiddifyctl-darwin-arm64) echo "hiddifyctl · macOS Apple Silicon (CLI)" ;;
    hiddifyctl-windows-amd64.exe) echo "hiddifyctl · Windows x64 (CLI)" ;;
    Hiddify-OpenHarmony.hap) echo "OpenHarmony / HarmonyOS · HAP" ;;
    Hiddify-OpenHarmony-Installer.zip) echo "OpenHarmony / HarmonyOS · 安装包 (ZIP)" ;;
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
ohos_listed=
listed_names="$(mktemp)"
add_row() {  # $1=name  $2=size_label
  echo "| $(describe "$1") | [\`$1\`](${download_base}/$1) | $2 |"
  echo "$1" >> "$listed_names"
  case "$(describe "$1")" in
    *OpenHarmony*) ohos_listed=1 ;;
  esac
}

if [ -d "$out_dir" ]; then
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    name="$(basename "$file")"
    [ -f "$file" ] || continue
    found=1
    add_row "$name" "$(size_of "$file")"
  done < <(find "$out_dir" -maxdepth 1 -type f | sort)
fi

# 并入已经在 release 里、但本轮没有产出的资产（平台腿本轮跳过/取消，但产物仍发布）。
# 让下载表如实反映“能下到的”内容，而不是只列本轮 out/ 里的。
if [ -n "$existing_assets_file" ] && [ -f "$existing_assets_file" ]; then
  while IFS=$'\t' read -r aname asize; do
    [ -n "$aname" ] || continue
    grep -qxF "$aname" "$listed_names" && continue
    found=1
    sz="$(awk -v b="$((${asize:-0}))" 'BEGIN { printf "%d MB", b / 1048576 }')"
    [ "$sz" = "0 MB" ] && sz="-"
    add_row "$aname" "$sz"
  done < "$existing_assets_file"
fi
rm -f "$listed_names"

if [ "$found" -eq 0 ]; then
  echo "| — | *没有产物* | — |"
fi

# OpenHarmony / HarmonyOS：下载表里出现 OHOS 行时才补这段签名说明。
if [ -n "${ohos_listed:-}" ]; then
  echo
  echo "## OpenHarmony / HarmonyOS 签名说明"
  echo
  echo "本发布的 \`Hiddify-OpenHarmony.hap\` / \`Hiddify-OpenHarmony-Installer.zip\` 是用本地自签名"
  echo "keystore（local-debug）签的，**只能装 OpenHarmony 设备 / 模拟器**；真机 HarmonyOS 会因"
  echo "profile 与 AGC 签名证书不匹配而拒装。核心库 \`hiddify-lib-ohos.tar.gz\` 发布在"
  echo "[核心仓库的 v5.5.5](https://github.com/ShuttleSpace/hiddify-core/releases/tag/v5.5.5)。"
  echo
  echo "要装真机，按 \`docs/harmonyos.md\` 配置 AppGallery Connect 后用 AGC 材料重签（命令行）："
  echo
  echo '```bash'
  echo '# 方式 A：切到 AGC 签名配置后用 hvigor 重建（推荐，自动签名）'
  echo '# 需要 ohos/secrets/{hiddify-app.p12, hiddify-app-agc.cer, hiddify-app-agc.p7b}'
  echo 'bash ohos/signature/use-signing.sh default'
  echo 'flutter build app --release --build-name=5.5.5 --build-number=50505'
  echo ''
  echo '# 方式 B：离线对已有 unsigned HAP 用 AGC 材料重签'
  echo 'JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home'
  echo 'HAP_TOOL=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar'
  echo 'S=ohos/secrets'
  echo '"$JAVA_HOME/bin/java" -jar "$HAP_TOOL" sign-app \'
  echo '  -mode localSign \'
  echo '  -keyAlias "hiddify-app" \'
  echo '  -signAlg SHA256withECDSA \'
  echo '  -appCertFile "$S/hiddify-app-agc.cer" \'
  echo '  -profileFile "$S/hiddify-app-agc.p7b" \'
  echo '  -keystoreFile "$S/hiddify-app.p12" \'
  echo '  -keystorePwd "<keystore 明文口令>" \'
  echo '  -keyPwd      "<key 明文口令>" \'
  echo '  -inFile  ohos/entry/build/default/outputs/default/entry-default-unsigned.hap \'
  echo '  -outFile build/ohos/app/entry-default-signed.hap \'
  echo '  -signCode 1'
  echo '```'
  echo
  echo '> `-appCertFile` 要 leaf 在前的证书链、`sign-app` 至少 2 级；AGC 下载顺序相反，用前需反转。'
  echo '> 私钥仍在本地 `hiddify-app.p12`，口令走 `-keystorePwd/-keyPwd`（或用 `sign-with-keystore.sh` 派生到 hvigor）。'
  echo
  echo "> 注：核心的 gRPC 控制面能在 OHOS 上运行，但**隧道/VPN 尚未实现**（缺少"
  echo "> \`type: \"vpn\"\` 的 extension ability），所以现在还不能真正转发流量。"
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
