#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
# SPDX-License-Identifier: BSD-3-Clause
#
# Build an Itinerary APK locally, mirroring KDE's craft-android CI job.
#
# Usage: tools/android/build-apk.sh [arm64|x86_64] [deps|app|package|all|shell]
#   deps     install dependencies (prebuilt from the KDE Craft cache where possible)
#   app      build itinerary from this checkout
#   package  produce the APK (unsigned) in the workspace apk/ dir
#   all      deps + app + package (default)
#   shell    open a shell in the build container
#   install  sign the APK with the Android debug key and install it via adb (runs on the host)
#   intl     rebuild libintl-lite from LIBINTL_LITE_SRC and KI18n, which links it statically
#            (needed for working plural form translations until that fix is in Craft;
#            run it again after 'deps', which restores the cached versions)
#   kpt      rebuild KPublicTransport from KPT_SRC, our branch with elevation, turn instructions and
#            booking links (run 'app' afterwards, and again after 'deps'). To create KPT_SRC:
#              git clone --branch v26.08.3 https://invent.kde.org/libraries/kpublictransport.git
#              git -C kpublictransport apply ../itinary/tools/android/patches/kpublictransport/*.patch
#   kirigami rebuild Kirigami at the version Craft uses with our patches from tools/android/patches/kirigami
#            (run 'app' afterwards, and again after 'deps')
#   kosm     the same for KOSMIndoorMap, with the patches from tools/android/patches/kosmindoormap
#
# Workspace (craft root, downloads, build dirs) lives next to the checkout in ../itinary-craft (override with ITINERARY_CRAFT_DIR); it must stay outside the source tree, as packaging scans the tree for AndroidManifest files.
set -euo pipefail

ARCH="${1:-arm64}"
STEP="${2:-all}"
IMAGE="${ITINERARY_ANDROID_IMAGE:-invent-registry.kde.org/sysadmin/ci-images/android-qt611:latest}"

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WS="${ITINERARY_CRAFT_DIR:-$(dirname "$SRC")/itinary-craft}"
# libintl-lite checkout with plural form support, based on the revision Craft uses
LIBINTL_LITE_SRC="${LIBINTL_LITE_SRC:-$(dirname "$SRC")/libintl-lite-craft}"
# KPublicTransport checkout with our changes not yet in a KDE release
KPT_SRC="${KPT_SRC:-$(dirname "$SRC")/kpublictransport-integration}"
TARGET="android-${ARCH}-clang"

mkdir -p "$WS/downloads"
[ -d "$WS/craftmaster" ] || git clone https://invent.kde.org/packaging/craftmaster.git "$WS/craftmaster"
[ -d "$WS/craft-ci" ]    || git clone --depth=1 https://invent.kde.org/sysadmin/craft-ci.git "$WS/craft-ci"

# Local overrides on top of KDE's CI config: download dir inside the workspace.
cat > "$WS/local-override.ini" <<EOF
[$TARGET]
Paths/DownloadDir = /craft/downloads/
EOF

if [ "$STEP" = "install" ]; then
    BT="$(ls -d "${ANDROID_HOME:-/opt/android-sdk}"/build-tools/*/ | sort -V | tail -1)"
    case "$ARCH" in arm64) ABI=arm64-v8a ;; *) ABI="$ARCH" ;; esac
    APK="$WS/apk/itinerary-app-$ABI.apk"
    SIGNED="$WS/apk/itinerary-app-$ABI-debugsigned.apk"
    "${BT}zipalign" -f -p 4 "$APK" "$SIGNED"
    "${BT}apksigner" sign --ks "$HOME/.android/debug.keystore" --ks-pass pass:android "$SIGNED"
    exec adb install -r "$SIGNED"
fi

read -r -d '' INNER <<'EOF' || true
set -euo pipefail
# NDK in the image is owner-only executable, so we run as root and hand files back.
trap 'chown -R "$HOST_UID:$HOST_GID" /craft' EXIT
git config --global --add safe.directory '*'
cd /craft
cm() {
  python3 -u craftmaster/CraftMaster.py \
    --config craft-ci/qt6/CraftConfig.ini \
    --config-override /src/.craft.ini \
    --config-override /craft/local-override.ini \
    --target "$TARGET" "$@"
}
OPTS=(--options itinerary.srcDir=/src)
# build a package at the version Craft uses, with our patches from tools/android/patches/<name>
patched() {
  local name="$1" package="$2" repo="$3" v
  v="$(cm -c -q --get version "$package" | tail -1)"
  rm -rf "/craft/src/$name"
  git clone --quiet --depth 1 --branch "v$v" "$repo" "/craft/src/$name"
  for patch in "/src/tools/android/patches/$name"/*.patch; do
    if [ -f "$patch" ]; then
      git -C "/craft/src/$name" apply "$patch"
    fi
  done
  cm -c --no-cache --compile --install --qmerge --options "$package.srcDir=/craft/src/$name" "$package"
}
case "$STEP" in
  deps)    cm --setup; cm -c -i craft; cm -c --install-deps itinerary ;;
  app)     cm -c --no-cache --compile --install --qmerge "${OPTS[@]}" itinerary ;;
  package) cm -c --package "${OPTS[@]}" itinerary
           ls -l /craft/*/apk/ 2>/dev/null || true ;;
  all)     cm --setup; cm -c -i craft; cm -c --install-deps itinerary
           cm -c --no-cache "${OPTS[@]}" itinerary
           cm -c --package "${OPTS[@]}" itinerary ;;
  intl)    cm -c --no-cache --compile --install --qmerge --options libs/libintl-lite.srcDir=/libintl-lite libs/libintl-lite
           # build from a local checkout, as fetching the source archive is broken in Craft
           [ -d /craft/src/ki18n ] || git clone --depth 1 --branch "v$(cm -c -q --get version kde/frameworks/tier1/ki18n | tail -1)" \
               https://invent.kde.org/frameworks/ki18n.git /craft/src/ki18n
           cm -c --no-cache --compile --install --qmerge --options kde/frameworks/tier1/ki18n.srcDir=/craft/src/ki18n kde/frameworks/tier1/ki18n ;;
  kirigami) patched kirigami kde/frameworks/tier1/kirigami https://invent.kde.org/frameworks/kirigami.git ;;
  kosm)    patched kosmindoormap kde/libs/kosmindoormap https://invent.kde.org/libraries/kosmindoormap.git ;;
  kpt)     cm -c --no-cache --compile --install --qmerge --options kde/libs/kpublictransport.srcDir=/kpublictransport kde/libs/kpublictransport ;;
  shell)   bash ;;
  *) echo "unknown step: $STEP" >&2; exit 2 ;;
esac
EOF

INTL_MOUNT=()
[ -d "$LIBINTL_LITE_SRC" ] && INTL_MOUNT=(-v "$LIBINTL_LITE_SRC:/libintl-lite")
[ -d "$KPT_SRC" ] && INTL_MOUNT+=(-v "$KPT_SRC:/kpublictransport")

TTY=()
[ -t 0 ] && TTY=(-it)

exec docker run --rm "${TTY[@]}" \
  --user 0:0 \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -e HOME=/craft/home -e TARGET="$TARGET" -e STEP="$STEP" \
  -v "$SRC:/src" \
  -v "$WS:/craft" \
  "${INTL_MOUNT[@]}" \
  "$IMAGE" bash -c "mkdir -p /craft/home; $INNER"
