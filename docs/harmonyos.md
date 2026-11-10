# HarmonyOS / OpenHarmony (ohos) support

The `ohos/` directory is an OpenHarmony Stage-model project that wraps the Flutter app for
the `ohos` platform. It is built with the OpenHarmony Flutter fork, not upstream Flutter:

```
~/.puro/envs/ohos/flutter        # Flutter 3.41.10-ohos-1.0.1, pinned by .puro.yaml
```

`flutter build app` (the `.app` package) and `flutter build hap` (the single HAP) both work.
Only the `ohos` target is supported; `flutter create --platforms ohos` is not used here.

## Building

The OHOS toolchain is picked up from DevEco Studio, and the signing JVM must be DevEco's
JBR 25 — the JDK on `PATH` rejects the zip64 extra field in the HAP with
`Invalid CEN header (invalid zip64 extra data field size)`.

```bash
export HOS_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
  PATH="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin:$HOME/.puro/envs/ohos/flutter/bin:$PATH"

flutter build app --release --build-name=5.0.0 --build-number=50000
```

`flutter build app` copies only `ohos-default-signed.app` into `build/ohos/app/`. The variant
whose inner HAPs are signed as well — `ohos-default-all-signed.app` — is the installable one
and has to be copied over by hand:

```bash
cp ohos/build/outputs/default/ohos-default-all-signed.app build/ohos/app/
cp ohos/entry/build/default/outputs/default/entry-default-signed.hap build/ohos/app/
```

The `all-signed` variant exists because `app.buildModeSet[release].buildOption.packOptions.appWithSignedPkg`
has to be `true` for hvigor to sign the inner HAPs as well.

Verified on 5.5.5 (`flutter build app --release --build-name=5.5.5 --build-number=50505`):
`ohos-default-all-signed.app` and `entry-default-signed.hap` build and pass
`hap-sign-tool verify-app` ("Verify success").

### Build gotchas

- **SDK snapshot mismatch.** If `flutter --version` exits non-zero with
  `Wrong full snapshot version, expected '…'`, the cached `flutter_tools.snapshot` is
  stale relative to the bundled Dart SDK. Remove `bin/cache/flutter_tools.snapshot` and
  `bin/cache/flutter_tools.stamp` (they are symlinks into the puro shared cache) and run
  `flutter --version` once to recompile the tool against the current Dart SDK.
- **`pub get` must use `PUB_HOSTED_URL=https://pub.dev` with the OHOS SDK.** The fork
  defaults to `pub.flutter-io.cn`, which lacks `image_picker_ios` (in the lock, so pub
  still fetches it), and `flutter build` re-runs `pub get`. Running the OHOS SDK's
  `pub get` also regenerates `.flutter-plugins-dependencies` *with* the `ohos` platform
  section — the hvigor Flutter plugin reads `.plugins.ohos.filter(...)` and throws
  `Cannot read properties of undefined (reading 'filter')` if that key is absent (which
  it is when the file was written by upstream Flutter). The committed `pubspec.lock` is
  the upstream-Flutter resolution; the OHOS `pub get` rewrites it, so restore it after.
- **`TargetPlatform.ohos`.** The OHOS Flutter SDK adds `TargetPlatform.ohos` to the
  enum, so an exhaustive `switch (defaultTargetPlatform)` fails to compile under it
  (`The type 'TargetPlatform' is not exhaustively matched … doesn't match
  'TargetPlatform.ohos'`). A `TargetPlatform.ohos` case cannot be written, since that
  value does not exist in upstream Flutter. Use a trailing wildcard `_ =>` for the
  mobile default (android/fuchsia): it catches `ohos` on the OHOS fork and stays
  exhaustive with no dead code on upstream. `PlatformUtils.isOhos`
  (`Platform.operatingSystem == 'ohos'`) is the runtime check when the enum is not
  needed.

## Signing

Two signing configs live in `ohos/build-profile.json5`:

| Config | Certificates | Profile | Installable on |
|---|---|---|---|
| `default` | AGC-issued chain (`secrets/hiddify-app-agc.cer`) | AGC-issued `.p7b` | real HarmonyOS devices |
| `local-debug` | locally built chain (`secrets/hiddify-app.cer`) | locally signed `.p7b` | OpenHarmony devices and emulators only |

Switch with:

```bash
ohos/signature/use-signing.sh default        # AGC (the default, what ships)
ohos/signature/use-signing.sh local-debug    # local self-signed chain
```

`default` fails with `00303107 Configuration Error` until the AGC profile is in place.

Everything secret lives in `ohos/secrets/`, which is git-ignored:

```
ohos/secrets/
  hiddify-app.p12        keystore: private key + self-signed app certificate
  hiddify-app.csr        certificate signing request for that key
  material/              hvigor's encrypted-password material (fd/ + ac/ + ce/)
  hiddify-app-agc.cer    AGC certificate chain (leaf + Huawei CBG CAs), leaf first
  hiddify-app-agc.p7b    AGC provision profile          <- still missing
  hiddify-app.cer        local application chain (leaf + local root CA)
  hiddify-app.p7b        local provision profile
  root-ca.cer            local root CA
  profile-ks.p12         keystore for the profile CA chain
```

The plaintext keystore password never lands on disk. `build-profile.json5` stores it as a
ciphertext hex that hvigor decrypts with the key derived from `secrets/material/`. Set it up
with:

```bash
KEYSTORE_PASSWORD='<the keystore password>' ohos/signature/sign-with-keystore.sh
```

That script re-issues the local certificate chain from the keystore's own private key, signs
the provision profile, derives the encrypted password, and rewrites the signing config.

### Two things the sign tool insists on

`hap-sign-tool.jar` is stricter than it looks:

- `sign-app` requires `-appCertFile` to be a **chain** of at least two certificates, and the
  root must carry CA basic constraints. The single self-signed certificate inside the
  keystore satisfies neither, so `sign-with-keystore.sh` issues a local root CA and an
  application certificate from the same private key and chains them. The private key still
  comes from the keystore, so the CSR stays valid for AGC.
- `sign-profile` requires a three-level chain (leaf + sub CA + root CA) for
  `-profileCertFile`, which is why the profile CA chain lives in its own keystore
  (`secrets/profile-ks.p12`).

Note that the sign tool does **not** check that the profile's `development-certificate`
matches the application certificate chain. Signing succeeds either way, but a real device
rejects the package because the two do not match.

### AGC certificates and profiles

The certificate comes from AppGallery Connect: upload the CSR, and AGC returns a `.cer`
chain. The matching provision profile (`.p7b`) comes from the same download, but it is a
separate file and is easy to miss — without it nothing installs on a real device.

AGC's download order is root CA first, then intermediate, then leaf. `certpath` wants the
**leaf first**, so the chain has to be reversed before it is used.

## Permissions

`ohos/entry/src/main/module.json5` declares what the app asks for:

| Permission | Kind | Why |
|---|---|---|
| `ohos.permission.INTERNET` | system_grant / normal | networking |
| `ohos.permission.MANAGE_VPN` | system_grant / system_basic | the VPN extension is the only workable tunnel on HarmonyOS |
| `ohos.permission.GET_NETWORK_STATS` | system_grant / system_basic | traffic history |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | system_grant / normal | keep the tunnel alive |
| `ohos.permission.GET_NETWORK_INFO` | system_grant / normal | local address, LAN sharing |
| `ohos.permission.GET_WIFI_INFO` | system_grant / normal | Wi-Fi vs. cellular |
| `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY` | user_grant | import and export of subscription files |

`GET_NETWORK_STATS` is the only one that needs an ACL application. It is on Huawei's
restricted-permission list, where "VPN applications querying traffic consumption" is an
explicitly allowed use case, and it takes about three working days to review.

The flow in AGC is: apply for the ACL under the project's **ACL permissions** tab, wait for
approval, then create the profile and tick **restricted ACL permissions** so the granted
permissions land in the profile's `acls.allowed-acls`. Permissions that are `user_grant`
belong in the profile's `permissions.restricted-permissions` instead and are asked for at
runtime; those need a `reason` and a `usedScene` in `module.json5`, and the `reason` has to
be a `$string:` resource in every localisation.

SDK-side reference for what each permission means: `PermissionDefinitions.json` under
`openharmony/toolchains/lib/`, and `UnsgnedDebugProfileTemplate.json` next to it shows the
shape of a provision profile.

## Plugins

The OHOS implementations of the plugins this app uses ship as separate `<plugin>_ohos`
packages, published on the `pub.flutter-io.cn` mirror. They are declared as plain
dependencies in `pubspec.yaml`; flutter registers them for the `ohos` platform only and the
other platforms keep using their own implementations.

Two shapes exist, and neither needs the main package to be patched:

- **Federated** (`implements: <plugin>`) — `path_provider_ohos`, `shared_preferences_ohos`,
  `url_launcher_ohos`, `share_plus_ohos`. Adding the dependency is enough.
- **App-facing** (only `platforms: ohos`) — `file_picker_ohos`, `package_info_plus_ohos`,
  `app_links_ohos`, `flutter_secure_storage_ohos`, `flutter_native_splash_ohos`. The native
  side serves the same MethodChannel the main package already talks to
  (`miguelruivo.flutter.plugins.filepicker`, `dev.fluttercommunity.plus/package_info`,
  `com.llfbandit.app_links/messages`, `plugins.it_nomads.com/flutter_secure_storage`), so
  the main package's Dart side works unchanged.

`file_picker` is the one exception: its Dart side is a `late` singleton with no default and
the generated ohos registrant does not register it, so `FilePicker.platform` would throw a
`LateInitializationError`. `lib/bootstrap.dart` registers `FilePickerIO` for ohos, which is
the same MethodChannel implementation the other platforms use.

Three version constraints had to be worked around in `dependency_overrides`:

| Override | Reason |
|---|---|
| `flutter_secure_storage_platform_interface: ^2.1.1` | `flutter_secure_storage_ohos` 1.0.0 asks for 1.x |
| `flutter_secure_storage_windows: 4.1.0` | 4.2.x wants win32 6.x, which renames `HLOCAL` |
| `win32: ^5.12.0` | `file_picker_ohos` 1.0.1 is still on win32 4.x |

`share_plus` also had to move from 10.x to 13.x, because `share_plus_ohos` needs
`share_plus_platform_interface` 7.x. Its API changed with it, so the single call site in
`lib/utils/uri_utils.dart` now uses `SharePlus.instance.share(ShareParams(...))`.

`file_picker_ohos` pulls in `image_picker` transitively. The app does not use it, but it
adds a pod, so `ios/Podfile.lock` and `macos/Podfile.lock` need regenerating with
`pod install` after a dependency change.

## What is still missing

- **`hiddify-core` has no OHOS build.** The Makefile in `hiddify-core/` only has desktop and
  mobile targets, and the HAP ships only `libapp.so` and `libflutter.so`. `getCoreInterface()`
  checks `Platform.isAndroid || Platform.isIOS`, which are both false on OHOS, so the app falls
  through to `CoreInterfaceDesktop` and calls `DynamicLibrary.open("hiddify-core.so")` — a
  file that is not there. **The proxy does not run on OHOS yet**, on phone or desktop.
  Fixing it means building the core for OHOS `arm64` and `x86_64` and adding an ohos branch
  to `lib/hiddifycore/core_interface/core_interface_wrapper.dart`.
- **No VPN extension ability.** `ohos.permission.MANAGE_VPN` is declared, but the app has
  no `extensionAbilities` entry of `type: "vpn"` and no `VpnExtensionAbility`, so it cannot
  open a tunnel yet. Note that the extension type in the API 26 schema is `vpn`; the
  `vpn.extension` spelling found in older material is not valid.
- **Desktop (2in1 / HarmonyOS PC) is not configured.** The toolchain supports it —
  `flutter build hap --target-platform ohos-x64` produces an x86_64 HAP, hvigor knows the
  `pc` and `2in1` device types, and the API 26 `module.json` schema accepts `2in1` — but
  `ohos/entry/src/main/module.json5` only declares `deviceTypes: ["phone"]`.

## Verifying a signature

```bash
export JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
"$JAVA_HOME/bin/java" -jar /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar \
  verify-app -inFile build/ohos/app/entry-default-signed.hap \
  -outCertChain /tmp/chain.cer -outProfile /tmp/profile.p7b
```

`verify: Verify success` means the package is signed; it does not say anything about whether
the profile and the certificate match each other.
