#!/usr/bin/env bash
# 切换 ohos/build-profile.json5 里 product 用的签名配置。
#
# 用法： ./use-signing.sh default        # AGC 正式签名（真机 HarmonyOS）
#        ./use-signing.sh local-debug   # 本地自签名（OpenHarmony 设备/模拟器）
#
# 配置文件里定义了两套 signingConfigs：
#   default      certpath = AGC 证书链, profile = AGC 的 p7b
#   local-debug  certpath = 本地自签证书链, profile = 本地自签的 p7b

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OHOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_PROFILE="$OHOS_DIR/build-profile.json5"

TARGET="${1:-}"
case "$TARGET" in
  default|local-debug) ;;
  *)
    echo "用法: $0 <default|local-debug>" >&2
    exit 1
    ;;
esac

python3 - "$BUILD_PROFILE" "$TARGET" <<'PYEOF'
import re, sys

path, target = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()

m = re.search(r'("signingConfig"\s*:\s*)"[^"]*"', src)
if not m:
    raise SystemExit("build-profile.json5 里找不到 product 的 signingConfig 字段")
src = src[:m.start()] + m.group(1) + '"%s"' % target + src[m.end():]
open(path, "w", encoding="utf-8").write(src)
print("product.signingConfig = %s" % target)
PYEOF
