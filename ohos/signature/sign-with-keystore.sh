#!/usr/bin/env bash
# 用 ohos/secrets 下的密钥库（DevEco / AGC 生成的 p12）配置本项目的鸿蒙签名。
#
# 用法： ./sign-with-keystore.sh [bundleName]
#
# 明文口令的来源（按优先级）：
#   1. 环境变量 KEYSTORE_PASSWORD
#   2. 本脚本的第一个位置参数
#   3. 交互式输入（不回显）
# 口令不会落盘，也不会出现在 ps 输出里 —— 脚本自己只用环境变量传给 openssl；
# hap-sign-tool 的 CLI 强制要求口令走命令行参数，那一段只在本地进程表里短暂可见。
#
# bundleName 形如 app.hiddify.com，须与 ohos/AppScope/app.json5 一致。
#
# 为什么不能直接用密钥库里那张自签名证书：
#   hap-sign-tool 的 sign-app 要求 -appCertFile 是一条**证书链**（≥2 张），
#   而且链根必须带 CA 属性的 basicConstraints；密钥库里那张 CN=hiddify-app 的
#   自签名证书两条都不满足（单张、且没有 basicConstraints）。
#   所以这里用**同一把私钥**再签发一张本地根 CA 和一张应用证书：
#     - 根 CA  : 用密钥库里的 hiddify-app 这把钥匙自签（CA:true）
#     - 应用证书: 同一把钥匙，由上面的根 CA 签发（codeSignature）
#   链 = 应用证书 + 根 CA。私钥始终来自密钥库，所以 ohos/secrets/hiddify-app.csr
#   与之匹配，上传到 AGC 换正式证书也不受影响。
#
#   p7b 那边另有一套 Profile CA 链（根CA/子CA/Profile 三把钥匙，单独放在
#   profile-ks.p12 里），因为 hap-sign-tool 的 sign-profile 明确要求
#   -profileCertFile 是「三级链」：叶子 + 子CA + 根CA。
#
# 产出（全部在 ohos/secrets/ 下，已 gitignore）：
#   root-ca.cer                根 CA（由密钥库的私钥签出）
#   app-leaf.cer               应用证书（CN=hiddify-app，codeSignature）
#   hiddify-app.cer            应用证书链 = 应用证书 + 根 CA
#   profile-ks.p12             Profile CA 链密钥库
#   root-ca-profile.cer        Profile 根 CA
#   sub-profile-sign-srv-ca.cer Profile 签名子 CA
#   profile-cert.cer           Profile 证书链（叶子+子CA+根CA）
#   hiddify-app.p7b            签好的 Provision Profile
#
# 明文口令不落盘：build-profile.json5 里存的是密文 hex，
# 解密密钥由 secrets/material/ 派生，见 derive-store-password.js。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OHOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="$OHOS_DIR/secrets"
P12="$SECRETS_DIR/hiddify-app.p12"
CER="$SECRETS_DIR/hiddify-app.cer"
APP_LEAF="$SECRETS_DIR/app-leaf.cer"
ROOT_CA="$SECRETS_DIR/root-ca.cer"
MATERIAL_DIR="$SECRETS_DIR/material"
PROFILE_KS="$SECRETS_DIR/profile-ks.p12"
PROFILE_ROOT_CA="$SECRETS_DIR/root-ca-profile.cer"
PROFILE_SUB_CA="$SECRETS_DIR/sub-profile-sign-srv-ca.cer"
PROFILE_CERT="$SECRETS_DIR/profile-cert.cer"
PROFILE_P7B="$SECRETS_DIR/hiddify-app.p7b"
PROFILE_JSON="$SECRETS_DIR/hiddify-app-profile.json"
BUILD_PROFILE="$OHOS_DIR/build-profile.json5"

BUNDLE_NAME="${1:-app.hiddify.com}"

# 明文口令：环境变量 > 位置参数 > 交互输入
PASSWORD="${KEYSTORE_PASSWORD:-${2:-}}"
if [[ -z "$PASSWORD" ]]; then
  if [[ -t 0 ]]; then
    read -r -s -p "密钥库口令: " PASSWORD
    echo
  fi
fi
if [[ -z "$PASSWORD" ]]; then
  echo "用法: KEYSTORE_PASSWORD=xxx $0 [bundleName]" >&2
  echo "      或: $0 <bundleName> <密钥库密码>" >&2
  exit 1
fi
export KEYSTORE_PASSWORD="$PASSWORD"
for f in "$P12" "$MATERIAL_DIR"; do
  [[ -e "$f" ]] || { echo "ERROR: 找不到 $f" >&2; exit 1; }
done

HAP_SIGN_TOOL="${HAP_SIGN_TOOL:-}"
if [[ -z "$HAP_SIGN_TOOL" ]]; then
  for candidate in \
    "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar" \
    "$HOME/Library/OpenHarmony/Sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"; do
    if [[ -f "$candidate" ]]; then HAP_SIGN_TOOL="$candidate"; break; fi
  done
fi
[[ -n "$HAP_SIGN_TOOL" ]] || { echo "ERROR: hap-sign-tool.jar 未找到" >&2; exit 1; }

KEY_ALIAS_APP="hiddify-app"
KEY_ALIAS_CA="hiddify_root_ca"
KEY_ALIAS_SUB_CA="hiddify_profile_sub_ca"
KEY_ALIAS_PROFILE="hiddify_profile"
SUBJECT_ROOT="C=CN,O=Hiddify,OU=OHOS,CN=Hiddify OHOS Root CA"
SUBJECT_APP="C=CN,O=Hiddify,OU=OHOS,CN=hiddify-app"
SUBJECT_PROFILE_ROOT="C=CN,O=Hiddify,OU=OHOS,CN=Hiddify OHOS Profile Root CA"
SUBJECT_PROFILE_SUB="C=CN,O=Hiddify,OU=OHOS,CN=Hiddify OHOS Profile Signing CA"
SUBJECT_PROFILE="C=CN,O=Hiddify,OU=OHOS,CN=Hiddify OHOS Profile"
VALIDITY_DAYS=3650

# Profile CA 链用的独立口令，与应用密钥库无关
PROFILE_KS_PWD="hiddify-ohos-profile-ca-2026"

sign_tool() { java -jar "$HAP_SIGN_TOOL" "$@"; }

echo "==> 1/6 用密钥库里的私钥签出本地根 CA"
rm -f "$ROOT_CA" "$APP_LEAF" "$CER" "$PROFILE_KS" "$PROFILE_ROOT_CA" "$PROFILE_SUB_CA" \
  "$PROFILE_CERT" "$PROFILE_P7B" "$PROFILE_JSON"
sign_tool generate-ca -keyAlias "$KEY_ALIAS_APP" -keyPwd "$PASSWORD" \
  -keyAlg ECC -keySize NIST-P-256 \
  -subject "$SUBJECT_ROOT" -validity "$VALIDITY_DAYS" -signAlg SHA256withECDSA \
  -keystoreFile "$P12" -keystorePwd "$PASSWORD" -basicConstraintsPathLen 3 \
  -outFile "$ROOT_CA" >/dev/null

echo "==> 2/6 签发应用证书（同一把私钥）"
sign_tool generate-cert -keyAlias "$KEY_ALIAS_APP" -keyPwd "$PASSWORD" \
  -issuer "$SUBJECT_ROOT" -issuerKeyAlias "$KEY_ALIAS_APP" -issuerKeyPwd "$PASSWORD" \
  -subject "$SUBJECT_APP" -validity "$VALIDITY_DAYS" \
  -keyUsage digitalSignature -keyUsageCritical false -extKeyUsage codeSignature \
  -signAlg SHA256withECDSA \
  -keystoreFile "$P12" -keystorePwd "$PASSWORD" \
  -outFile "$APP_LEAF" >/dev/null
cat "$APP_LEAF" "$ROOT_CA" > "$CER"
echo "    证书链 $(grep -c 'BEGIN CERTIFICATE' "$CER") 张 -> $(basename "$CER")"

echo "==> 3/6 生成 Profile CA 链"
sign_tool generate-keypair -keyAlias "$KEY_ALIAS_CA"      -keyPwd "$PROFILE_KS_PWD" -keyAlg ECC -keySize NIST-P-256 -keystoreFile "$PROFILE_KS" -keystorePwd "$PROFILE_KS_PWD" >/dev/null
sign_tool generate-keypair -keyAlias "$KEY_ALIAS_SUB_CA"  -keyPwd "$PROFILE_KS_PWD" -keyAlg ECC -keySize NIST-P-256 -keystoreFile "$PROFILE_KS" -keystorePwd "$PROFILE_KS_PWD" >/dev/null
sign_tool generate-keypair -keyAlias "$KEY_ALIAS_PROFILE" -keyPwd "$PROFILE_KS_PWD" -keyAlg ECC -keySize NIST-P-256 -keystoreFile "$PROFILE_KS" -keystorePwd "$PROFILE_KS_PWD" >/dev/null
sign_tool generate-ca -keyAlias "$KEY_ALIAS_CA" -keyPwd "$PROFILE_KS_PWD" \
  -keyAlg ECC -keySize NIST-P-256 \
  -subject "$SUBJECT_PROFILE_ROOT" -validity "$VALIDITY_DAYS" -signAlg SHA256withECDSA \
  -keystoreFile "$PROFILE_KS" -keystorePwd "$PROFILE_KS_PWD" -basicConstraintsPathLen 3 \
  -outFile "$PROFILE_ROOT_CA" >/dev/null
sign_tool generate-ca -keyAlias "$KEY_ALIAS_SUB_CA" -keyPwd "$PROFILE_KS_PWD" \
  -keyAlg ECC -keySize NIST-P-256 \
  -issuer "$SUBJECT_PROFILE_ROOT" -issuerKeyAlias "$KEY_ALIAS_CA" -issuerKeyPwd "$PROFILE_KS_PWD" \
  -subject "$SUBJECT_PROFILE_SUB" -validity "$VALIDITY_DAYS" -signAlg SHA256withECDSA \
  -keystoreFile "$PROFILE_KS" -keystorePwd "$PROFILE_KS_PWD" -basicConstraintsPathLen 0 \
  -outFile "$PROFILE_SUB_CA" >/dev/null
sign_tool generate-profile-cert -keyAlias "$KEY_ALIAS_PROFILE" -keyPwd "$PROFILE_KS_PWD" \
  -issuer "$SUBJECT_PROFILE_SUB" -issuerKeyAlias "$KEY_ALIAS_SUB_CA" -issuerKeyPwd "$PROFILE_KS_PWD" \
  -subject "$SUBJECT_PROFILE" -validity "$VALIDITY_DAYS" -signAlg SHA256withECDSA \
  -keystoreFile "$PROFILE_KS" -keystorePwd "$PROFILE_KS_PWD" \
  -outForm certChain -rootCaCertFile "$PROFILE_ROOT_CA" -subCaCertFile "$PROFILE_SUB_CA" \
  -outFile "$PROFILE_CERT" >/dev/null

echo "==> 4/6 生成 Provision Profile 并签名"
python3 - "$APP_LEAF" "$BUNDLE_NAME" "$PROFILE_JSON" <<'PYEOF'
import json, sys, time, uuid

cer_path, bundle, out = sys.argv[1:4]
raw = open(cer_path).read()
leaf = raw.split("-----END CERTIFICATE-----")[0] + "-----END CERTIFICATE-----\n"
now = int(time.time())
profile = {
    "version-name": "1.0.0",
    "version-code": 1,
    "uuid": str(uuid.uuid4()),
    "validity": {"not-before": now, "not-after": now + 3650 * 86400},
    "type": "debug",
    "bundle-info": {
        "developer-id": "Hiddify",
        "development-certificate": leaf,
        "bundle-name": bundle,
        "app-feature": "hos_normal_app",
        "apl": "normal",
    },
    "permissions": {"restricted-permissions": []},
    "debug-info": {"device-ids": []},
    "issuer": "pki_internal",
}
json.dump(profile, open(out, "w"), indent=2)
PYEOF
sign_tool sign-profile -mode localSign \
  -keyAlias "$KEY_ALIAS_PROFILE" -keyPwd "$PROFILE_KS_PWD" \
  -profileCertFile "$PROFILE_CERT" \
  -inFile "$PROFILE_JSON" -signAlg SHA256withECDSA \
  -keystoreFile "$PROFILE_KS" -keystorePwd "$PROFILE_KS_PWD" \
  -outFile "$PROFILE_P7B" >/dev/null
echo "    -> $(basename "$PROFILE_P7B")"

echo "==> 5/6 派生 hvigor 加密口令"
HEX="$(KEYSTORE_PASSWORD="$PASSWORD" node "$SCRIPT_DIR/derive-store-password.js" "$MATERIAL_DIR")"

echo "==> 6/6 更新 $BUILD_PROFILE"
HEX="$HEX" ALIAS="$KEY_ALIAS_APP" python3 - "$BUILD_PROFILE" <<'PYEOF'
import os, re, sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
hexpwd = os.environ["HEX"]
alias = os.environ["ALIAS"]

def set_field(block, key, value):
    pat = re.compile(r'("%s"\s*:\s*)"[^"]*"' % re.escape(key))
    if not pat.search(block):
        raise SystemExit("build-profile.json5 里找不到字段 %s" % key)
    return pat.sub(lambda m: m.group(1) + '"%s"' % value, block, count=1)

m = re.search(r'"signingConfigs"\s*:\s*\[.*?\]\s*,', src, re.S)
if not m:
    raise SystemExit("build-profile.json5 里找不到 signingConfigs")
block = m.group(0)
for key, value in (("storeFile", "secrets/hiddify-app.p12"),
                   ("storePassword", hexpwd),
                   ("keyAlias", alias),
                   ("keyPassword", hexpwd),
                   ("profile", "secrets/hiddify-app.p7b"),
                   ("certpath", "secrets/hiddify-app.cer"),
                   ("signAlg", "SHA256withECDSA")):
    block = set_field(block, key, value)
src = src[:m.start()] + block + src[m.end():]
open(path, "w", encoding="utf-8").write(src)
PYEOF

echo
echo "完成。signingConfigs 现在是："
sed -n '/"signingConfigs"/,/^    \]/p' "$BUILD_PROFILE"
echo
echo "注意：这是一条本地自建的证书链，只能装到 OpenHarmony 设备/模拟器；"
echo "      装到真机 HarmonyOS 需要 AGC 签发的证书与 profile。"
