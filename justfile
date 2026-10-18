# hiddify-app — build & release helpers (gh + git)
#
# `repo` defaults to the ShuttleSpace fork where CI runs. Override per-invocation:
#     just repo=owner/name draft
repo := "ShuttleSpace/hiddify-app"

# Git remote to push release tags to (`origin` already points to the fork here).
# Override with: just remote=NAME tag 1.2.3
remote := "origin"

# List all commands
default:
    @just --list

# ---------------------------------------------------------------------------
# CI / build triggers (workflow_dispatch)
# ---------------------------------------------------------------------------

# Trigger a manual build and publish a draft prerelease.
# Both `just draft 4.1.3` and `just draft version=4.1.3` are accepted.
draft version="draft":
    #!/usr/bin/env bash
    set -euo pipefail
    version='{{version}}'
    version="${version#version=}"
    gh workflow run manual-build.yml -R '{{repo}}' --ref dev -f "version=${version}" -f publish-prerelease=true

# Trigger a manual build (compile + upload artifacts, no release).
# Both `just build 4.1.3` and `just build version=4.1.3` are accepted.
build version="draft":
    #!/usr/bin/env bash
    set -euo pipefail
    version='{{version}}'
    version="${version#version=}"
    gh workflow run manual-build.yml -R '{{repo}}' --ref dev -f "version=${version}" -f publish-prerelease=false

# Trigger the CI workflow on a branch (dev by default)
ci branch="dev":
    gh workflow run ci.yml -R {{repo}} --ref {{branch}}

# ---------------------------------------------------------------------------
# Local builds
#
# `make *-libs` pulls a prebuilt core from a GitHub release, which is wrong for
# local work: the submodules are checked out, so a core change would not be in
# the artifact at all and every local build would test yesterday's core. These
# build it here and drop it where each platform's build already looks.
#
# The core Makefile cross-compiles, so every recipe runs on any host; the one
# thing that is host-specific is signing, which is why the Apple targets are
# kept separate rather than folded into a generic `ios`.
# ---------------------------------------------------------------------------

core := "hiddify-core"
android-libs := "android/app/libs"
ios-frameworks := "ios/Frameworks"

# Go + Flutter toolchain the core Makefile drives through. gomobile is installed
# by its `lib_install` prerequisite, which wants network on first run only.
#
# ANDROID_NDK_HOME must be exported: the core Makefile derives the NDK from it
# and cannot guess. The default SDK location is used when the shell has neither
# variable set, which is the common case on macOS.
export ANDROID_NDK_HOME := `ls -d "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"/ndk/* 2>/dev/null | sort -V | tail -1`

# Fail early and legibly rather than deep inside a gomobile error.
_require-android:
    #!/usr/bin/env bash
    if [ -z "$ANDROID_NDK_HOME" ]; then
      echo "no NDK found under ${ANDROID_HOME:-$HOME/Library/Android/sdk}; install one via the Android SDK manager" >&2
      exit 1
    fi

# AGP 8.11 rejects a Gradle that is not on JDK 17. The JDK is intentionally not
# pinned in gradle.properties — see the note there — so it comes from JAVA_HOME,
# and this says so in a sentence instead of leaving Gradle to reject a path.
_require-jdk-17:
    #!/usr/bin/env bash
    if [ -z "$JAVA_HOME" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
      echo "JAVA_HOME is unset or is not a JDK; AGP 8.11 needs JDK 17" >&2
      exit 1
    fi
    version="$("$JAVA_HOME/bin/java" -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')"
    if [ "$version" != "17" ]; then
      echo "JAVA_HOME is JDK $version; AGP 8.11 needs JDK 17" >&2
      echo "  current: $JAVA_HOME" >&2
      exit 1
    fi

# --- core libraries -------------------------------------------------------

# Universal macOS dylib, picked up straight from hiddify-core/bin by Xcode.
core-macos:
    make -C {{core}} -f Makefile macos

# One aar carrying every Android ABI, which is the single file gradle consumes.
core-android: _require-android
    make -C {{core}} -f Makefile android
    mkdir -p {{android-libs}}
    cp {{core}}/bin/hiddify-core.aar {{android-libs}}/hiddify-core.aar

# Device and simulator xcframeworks; ios-full adds tvOS and macOS.
core-ios:
    make -C {{core}} -f Makefile ios
    mkdir -p {{ios-frameworks}}
    rm -rf {{ios-frameworks}}/HiddifyCore.xcframework
    cp -R {{core}}/bin/hiddify-core.xcframework {{ios-frameworks}}/HiddifyCore.xcframework

core-ios-full:
    make -C {{core}} -f Makefile ios-full
    mkdir -p {{ios-frameworks}}
    rm -rf {{ios-frameworks}}/HiddifyCore.xcframework
    cp -R {{core}}/bin/hiddify-core.xcframework {{ios-frameworks}}/HiddifyCore.xcframework

core-linux:
    make -C {{core}} -f Makefile linux-archs

core-windows:
    make -C {{core}} -f Makefile windows-archs

core: core-macos core-linux core-windows

# Sentry's DSN is a compile-time define (`String.fromEnvironment` in
# lib/core/model/environment.dart). Always passing it keeps a local build the
# same shape as CI's; unset it becomes an empty string and Sentry stays off,
# which is the right default for a local build with no release secrets.
sentry := "--dart-define=sentry_dsn=" + env_var_or_default("SENTRY_DSN", "")

# --- apps -----------------------------------------------------------------

macos: core-macos
    flutter build macos --release {{sentry}}

macos-debug: core-macos
    flutter build macos --debug

android: _require-jdk-17 core-android
    flutter build apk --release {{sentry}}

apk: android

apk-debug: _require-jdk-17 core-android
    flutter build apk --debug

# Google Play needs the bundle rather than the apk.
aab: _require-jdk-17 core-android
    flutter build appbundle --release {{sentry}}

aab-debug: _require-jdk-17 core-android
    flutter build appbundle --debug

ios: core-ios
    flutter build ios --release --no-codesign {{sentry}}

# Device builds need a provisioning profile and are therefore not wrapped here.
ios-real: core-ios
    flutter build ipa {{sentry}}

# --- checks ---------------------------------------------------------------

# The Go unit tests cover the system proxy, which is the part of the core that
# is easy to break and hard to notice from the UI.
test-core:
    cd {{core}}/hiddify-sing-box && go test -race ./common/settings/

test:
    flutter test
    @just test-core

# Codegen, which is gitignored and absent from a fresh clone.
gen:
    flutter pub run build_runner build --delete-conflicting-outputs
    flutter pub run slang

fmt:
    cd {{core}}/hiddify-sing-box && gofmt -w common/settings/
    dart format --line-length 120 lib/

check:
    flutter analyze lib/
    @just test

clean-core:
    make -C {{core}} -f Makefile clean

clean: clean-core
    flutter clean

# ---------------------------------------------------------------------------
# Release / publish
# ---------------------------------------------------------------------------

# Create + push a release tag (triggers the Release workflow which builds & publishes)
tag version:
    git tag v{{version}}
    git push {{remote}} v{{version}}

# Full release: bump version files, commit, tag and push (wraps .github/change_version.sh)
release version:
    @echo "Releasing v{{version}} ..."
    @CORE_VERSION="$$(sed -n 's/^core\.version=//p' dependencies.properties)" GIT_REMOTE={{remote}} bash -c 'echo "{{version}}" | bash .github/change_version.sh'

# Create a GitHub release (generated notes) for an existing tag, without rebuilding
gh-release version:
    gh release create v{{version}} -R {{repo}} --generate-notes

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

# Watch the latest workflow run until it finishes
watch:
    gh run watch -R {{repo}}

# List recent workflow runs
runs:
    gh run list -R {{repo}} --limit 15
