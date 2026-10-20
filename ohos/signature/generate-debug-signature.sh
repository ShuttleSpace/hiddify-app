#!/usr/bin/env bash
# 生成 OHOS 本地调试签名材料（OpenHarmony 风格的自签名证书链 + Provision Profile）。
#
# 说明：hap-sign-tool.jar 的 generate-cert 在校验 issuerKeyAlias 时使用的是主密钥库
# （-issuerKeystoreFile 参数实际不生效），因此这里把根 CA / 子 CA / 应用 / Profile
# 四把钥匙全部放进同一个密钥库 hiddify-debug.p12。
#
# 产物（全部位于本目录）：
#   hiddify-debug.p12           统一密钥库（含全部私钥，切勿提交 git）
#   root-ca.cer                 根 CA 证书
#   sub-profile-sign-srv-ca.cer Profile 签名子 CA 证书
#   app-cert.cer                应用签名证书链（叶子 + 根 CA）
#   profile-cert.cer            Profile 签名证书链（叶子 + 子 CA + 根 CA）
#   debug-profile.json          未签名的 Provision Profile（JSON）
#   hiddify-debug.p7b           签名后的 Provision Profile
#
# 用法： ./generate-debug-signature.sh [bundleName]
#   bundleName 默认 app.hiddify.com（须与 ohos/AppScope/app.json5 一致）。
#
# 注意：本地签名产物只能安装在 OpenHarmony 设备/模拟器上；
#       真机 HarmonyOS 安装需使用华为 AGC 签发的调试证书（DevEco Studio 自动签名）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

HAP_SIGN_TOOL="${HAP_SIGN_TOOL:-}"
if [[ -z "$HAP_SIGN_TOOL" ]]; then
  for candidate in \
    "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar" \
    "$HOME/Library/OpenHarmony/Sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"; do
    if [[ -f "$candidate" ]]; then HAP_SIGN_TOOL="$candidate"; break; fi
  done
fi
if [[ -z "$HAP_SIGN_TOOL" ]]; then
  echo "ERROR: hap-sign-tool.jar not found; set HAP_SIGN_TOOL env var" >&2
  exit 1
fi

BUNDLE_NAME="${1:-app.hiddify.com}"
KEYSTORE="hiddify-debug.p12"
KEYSTORE_PWD="hiddify-ohos-debug-signing-key-2026-01"
KEY_ALIAS_APP="hiddify_debug"
KEY_ALIAS_PROFILE="hiddify_profile_debug"
KEY_ALIAS_CA="hiddify_root_ca"
KEY_ALIAS_SUB_CA="hiddify_profile_sub_ca"
SUBJECT_ROOT="C=CN,O=Hiddify,OU=OHOS,CN=Hiddify OHOS Root CA"
SUBJECT_SUB="C=CN,O=Hiddify,OU=OHOS,CN=Hiddify OHOS Profile Signing CA"
SUBJECT_APP="C=CN,O=Hiddify,OU=OHOS,CN=Hiddify OHOS Debug"
SUBJECT_PROFILE="C=CN,O=Hiddify,OU=OHOS,CN=Hiddify OHOS Debug Profile"
VALIDITY_DAYS=3650

sign_tool() { java -jar "$HAP_SIGN_TOOL" "$@"; }

rm -f "$KEYSTORE" root-ca.cer sub-profile-sign-srv-ca.cer app-cert.cer profile-cert.cer \
  debug-profile.json hiddify-debug.p7b app-leaf.cer

echo "==> 1/6 生成统一密钥库（根 CA / 子 CA / 应用 / Profile 四把钥匙）"
sign_tool generate-keypair -keyAlias "$KEY_ALIAS_CA"       -keyPwd "$KEYSTORE_PWD" -keyAlg ECC -keySize NIST-P-256 -keystoreFile "$KEYSTORE" -keystorePwd "$KEYSTORE_PWD"
sign_tool generate-keypair -keyAlias "$KEY_ALIAS_SUB_CA"   -keyPwd "$KEYSTORE_PWD" -keyAlg ECC -keySize NIST-P-256 -keystoreFile "$KEYSTORE" -keystorePwd "$KEYSTORE_PWD"
sign_tool generate-keypair -keyAlias "$KEY_ALIAS_APP"      -keyPwd "$KEYSTORE_PWD" -keyAlg ECC -keySize NIST-P-256 -keystoreFile "$KEYSTORE" -keystorePwd "$KEYSTORE_PWD"
sign_tool generate-keypair -keyAlias "$KEY_ALIAS_PROFILE"  -keyPwd "$KEYSTORE_PWD" -keyAlg ECC -keySize NIST-P-256 -keystoreFile "$KEYSTORE" -keystorePwd "$KEYSTORE_PWD"

echo "==> 2/6 生成根 CA 与 Profile 签名子 CA 证书"
sign_tool generate-ca -keyAlias "$KEY_ALIAS_CA" -keyPwd "$KEYSTORE_PWD" \
  -keyAlg ECC -keySize NIST-P-256 \
  -subject "$SUBJECT_ROOT" -validity "$VALIDITY_DAYS" -signAlg SHA256withECDSA \
  -keystoreFile "$KEYSTORE" -keystorePwd "$KEYSTORE_PWD" -basicConstraintsPathLen 3 \
  -outFile root-ca.cer
sign_tool generate-ca -keyAlias "$KEY_ALIAS_SUB_CA" -keyPwd "$KEYSTORE_PWD" \
  -keyAlg ECC -keySize NIST-P-256 \
  -issuer "$SUBJECT_ROOT" -issuerKeyAlias "$KEY_ALIAS_CA" -issuerKeyPwd "$KEYSTORE_PWD" \
  -subject "$SUBJECT_SUB" -validity "$VALIDITY_DAYS" -signAlg SHA256withECDSA \
  -keystoreFile "$KEYSTORE" -keystorePwd "$KEYSTORE_PWD" -basicConstraintsPathLen 0 \
  -outFile sub-profile-sign-srv-ca.cer

echo "==> 3/6 生成应用签名证书链（叶子 + 根 CA）"
sign_tool generate-cert -keyAlias "$KEY_ALIAS_APP" -keyPwd "$KEYSTORE_PWD" \
  -issuer "$SUBJECT_ROOT" -issuerKeyAlias "$KEY_ALIAS_CA" -issuerKeyPwd "$KEYSTORE_PWD" \
  -subject "$SUBJECT_APP" -validity "$VALIDITY_DAYS" \
  -keyUsage digitalSignature -keyUsageCritical false -extKeyUsage codeSignature \
  -signAlg SHA256withECDSA \
  -keystoreFile "$KEYSTORE" -keystorePwd "$KEYSTORE_PWD" \
  -outFile app-leaf.cer
cat app-leaf.cer root-ca.cer > app-cert.cer

echo "==> 4/6 生成 Profile 签名证书链（叶子 + 子 CA + 根 CA）"
sign_tool generate-profile-cert -keyAlias "$KEY_ALIAS_PROFILE" -keyPwd "$KEYSTORE_PWD" \
  -issuer "$SUBJECT_SUB" -issuerKeyAlias "$KEY_ALIAS_SUB_CA" -issuerKeyPwd "$KEYSTORE_PWD" \
  -subject "$SUBJECT_PROFILE" -validity "$VALIDITY_DAYS" \
  -signAlg SHA256withECDSA \
  -keystoreFile "$KEYSTORE" -keystorePwd "$KEYSTORE_PWD" \
  -outForm certChain -rootCaCertFile root-ca.cer -subCaCertFile sub-profile-sign-srv-ca.cer \
  -outFile profile-cert.cer

echo "==> 5/6 生成未签名 Provision Profile (bundle-name=$BUNDLE_NAME)"
NOT_BEFORE=$(date +%s)
NOT_AFTER=$((NOT_BEFORE + VALIDITY_DAYS * 86400))
PROFILE_UUID=$(python3 -c 'import uuid; print(uuid.uuid4())')
APP_LEAF_PEM=$(awk 'BEGIN{n=0} /^-----BEGIN CERTIFICATE-----/{n++} n==1{print} /^-----END CERTIFICATE-----/{if(n==1) exit}' app-cert.cer)
python3 - "$APP_LEAF_PEM" "$PROFILE_UUID" "$NOT_BEFORE" "$NOT_AFTER" "$BUNDLE_NAME" <<'PYEOF'
import json, sys
leaf, uuid, nb, na, bundle = sys.argv[1:6]
# 注意：命令替换 $(...) 会吃掉行尾换行，而 hap-sign-tool 的
# DigestUtils.decodeBase64ToX509Certifate 要求 PEM 以
# "-----END CERTIFICATE-----\n" 结尾才走 PEM 分支，否则落入 base64 解码
# 分支报 "Illegal base64 character 20"。因此这里显式补回车符。
if not leaf.endswith("\n"):
    leaf += "\n"
profile = {
    "version-name": "1.0.0",
    "version-code": 1,
    "uuid": uuid,
    "validity": {"not-before": int(nb), "not-after": int(na)},
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
with open("debug-profile.json", "w") as f:
    json.dump(profile, f, indent=2)
PYEOF

echo "==> 6/6 签名 Provision Profile -> hiddify-debug.p7b"
sign_tool sign-profile -mode localSign \
  -keyAlias "$KEY_ALIAS_PROFILE" -keyPwd "$KEYSTORE_PWD" \
  -profileCertFile profile-cert.cer \
  -inFile debug-profile.json -signAlg SHA256withECDSA \
  -keystoreFile "$KEYSTORE" -keystorePwd "$KEYSTORE_PWD" \
  -outFile hiddify-debug.p7b

rm -f app-leaf.cer
echo
echo "Done. Generated:"
ls -1 root-ca.cer sub-profile-sign-srv-ca.cer app-cert.cer profile-cert.cer debug-profile.json hiddify-debug.p7b
echo
echo "build-profile.json5 signingConfigs 应配置："
echo "  storeFile:     signature/$KEYSTORE"
echo "  keyAlias:      $KEY_ALIAS_APP"
echo "  keyPassword:   $KEYSTORE_PWD"
echo "  storePassword: $KEYSTORE_PWD"
echo "  certpath:      signature/app-cert.cer"
echo "  profile:       signature/hiddify-debug.p7b"
echo "  signAlg:       SHA256withECDSA"
