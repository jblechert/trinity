#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
# SPDX-License-Identifier: BSD-3-Clause
#
# Build the Itinerary app for iOS (arm64 devices, or the simulator with IOS_PLATFORM=simulator, see platform.sh),
# against the dependencies built by build-deps.sh for the same platform.
# The result is an unsigned app bundle, signing happens in Xcode by the publishing account.
#
# Usage: tools/ios/build-app.sh <Qt for iOS dir> <dependency prefix> [build dir]
#
# The bundle identifier and the name shown on the home screen can be overridden with
# ITINERARY_IOS_BUNDLE_IDENTIFIER and ITINERARY_IOS_DISPLAY_NAME.
set -euo pipefail

QT_IOS="$1"
PREFIX="$2"
BUILD="${3:-$PWD/ios-build}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=platform.sh
. "$SRC/tools/ios/platform.sh"
WORK="${IOS_WORK_DIR:-$PWD/ios-work}"
QT_HOST_PATH="${QT_HOST_PATH:-$(dirname "$QT_IOS")/macos}"
HOST_PREFIX="$PREFIX/host"
# the Breeze icons used by the app are compiled into it, see kirigami_package_breeze_icons()
BREEZE_ICONS_REF="v6.31.0"

mkdir -p "$PREFIX/logs" "$WORK"

# only find iOS libraries with pkg-config, not the ones installed on the host (e.g. by Homebrew)
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
unset PKG_CONFIG_PATH

if [ ! -d "$WORK/breeze-icons" ]; then
    git clone --quiet --depth 1 --branch "$BREEZE_ICONS_REF" https://invent.kde.org/frameworks/breeze-icons.git "$WORK/breeze-icons.tmp"
    mv "$WORK/breeze-icons.tmp" "$WORK/breeze-icons"
fi

log="$PREFIX/logs/itinerary-configure.log"
echo "== configuring itinerary"
if ! "$QT_IOS/bin/qt-cmake" -S "$SRC" -B "$BUILD" -G Ninja \
        -DQT_HOST_PATH="$QT_HOST_PATH" \
        -DQT_ADDITIONAL_PACKAGES_PREFIX_PATH="$PREFIX" \
        -DCMAKE_PREFIX_PATH="$PREFIX" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_MAJOR_VERSION=6 \
        -DCMAKE_OSX_SYSROOT="$IOS_SYSROOT" \
        -DCMAKE_OSX_ARCHITECTURES="$IOS_ARCH" \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DKF6_HOST_TOOLING="$HOST_PREFIX/lib/cmake" \
        -DBREEZEICONS_DIR="$WORK/breeze-icons" \
        -DITINERARY_IOS_BUNDLE_IDENTIFIER="${ITINERARY_IOS_BUNDLE_IDENTIFIER:-at.blechert.trinity}" \
        -DITINERARY_IOS_DISPLAY_NAME="${ITINERARY_IOS_DISPLAY_NAME:-Trinity}" \
        > "$log" 2>&1; then
    echo "!! configuring failed, last lines of $log:"
    tail -n 80 "$log"
    exit 1
fi

log="$PREFIX/logs/itinerary-build.log"
echo "== building itinerary"
# keep going to see as many errors as possible per CI run
if ! cmake --build "$BUILD" -- -k 0 > "$log" 2>&1; then
    echo "!! building failed, errors in $log:"
    grep -E -A5 'error:|FAILED:|Undefined symbols|ld: ' "$log" | head -n 300
    exit 1
fi

app="$(find "$BUILD/bin" "$BUILD/src/app" -maxdepth 1 -name '*.app' -type d 2>/dev/null | head -n 1)"
if [ -z "$app" ]; then
    echo "!! no app bundle found"
    exit 1
fi

# with the Ninja generator the launch screen is copied as is, but iOS needs it compiled
if [ -f "$app/LaunchScreen.storyboard" ]; then
    deployment_target="$(sed -n 's/^CMAKE_OSX_DEPLOYMENT_TARGET:[A-Z]*=//p' "$BUILD/CMakeCache.txt")"
    xcrun ibtool --compile "$app/LaunchScreen.storyboardc" "$app/LaunchScreen.storyboard" \
        --minimum-deployment-target "${deployment_target:-$IOS_DEPLOYMENT_TARGET}" --target-device iphone --target-device ipad
    rm "$app/LaunchScreen.storyboard"
fi
# KI18n and Qt find translations in the locale directory of the bundle; only languages the app is translated to are
# included, from the app's catalogs (built by ki18n_install()) and those of the dependencies (see build-deps.sh)
rm -rf "$app/locale"
for lang_dir in "$BUILD/locale"/*; do
    lang="$(basename "$lang_dir")"
    mkdir -p "$app/locale/$lang"
    cp -R "$lang_dir/." "$app/locale/$lang/"
    if [ -d "$PREFIX/share/locale/$lang" ]; then
        cp -R "$PREFIX/share/locale/$lang/." "$app/locale/$lang/"
    fi
done
# of the iso-codes catalogs, KI18n only uses those of countries and their subdivisions
find "$app/locale" -name 'iso_*.mo' ! -name 'iso_3166-1.mo' ! -name 'iso_3166-2.mo' -delete
# the country data of KI18n's locale data, found in the bundle like on Android in the APK assets
mkdir -p "$app/iso-codes/json"
cp "$PREFIX/share/iso-codes/json/iso_3166-1.json" "$PREFIX/share/iso-codes/json/iso_3166-2.json" "$app/iso-codes/json/"

echo "Built $app"
