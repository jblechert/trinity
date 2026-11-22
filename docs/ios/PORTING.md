# Porting this fork to iOS

Status: the dependencies and the app build in CI (`.github/workflows/ios.yml`) as an unsigned app bundle for
arm64 devices, uploaded as the `itinerary-ios-unsigned` workflow artifact, and for the simulator
(`itinerary-ios-simulator`). The CI starts the simulator build in the iOS Simulator and uploads screenshots and logs
(`ios-simulator-smoke-test`), see "Testing in the simulator". It has not been run on a device yet.

This document collects what an iPhone version of this fork needs, so the work can be picked up on a Mac.
KDE Itinerary itself has no iOS version, and KDE's build infrastructure (Craft CI) has no iOS target.

## Building

Everything is built with Qt's `qt-cmake` for iOS and Ninja, as static libraries, on a Mac with Xcode,
Qt for iOS and the matching desktop Qt (for host tools):

    tools/ios/build-deps.sh <Qt for iOS dir> <prefix>     # dependencies, see tools/ios/deps.txt
    tools/ios/build-app.sh <Qt for iOS dir> <prefix>      # the app, ios-build/bin/itinerary.app

`build-deps.sh` applies the fork's own changes to a library from `tools/android/patches/<package>/` (the same
KPublicTransport extensions as on Android), then the patches in `tools/ios/patches/<package>/` (fixes for iOS and
static builds, all meant to go upstream). It only rebuilds a package when its version, patches or arguments change.
The CI caches the prefix.
A changed patch of a library doesn't rebuild the packages depending on it; that is only a problem for patches of
generated code, e.g. ECM's translation loader.

Both scripts build for arm64 devices by default, and for the simulator with `IOS_PLATFORM=simulator` (see
`tools/ios/platform.sh`), which needs its own prefix and build directory. The simulator architecture is x86_64, as the
simulator slices of the Qt for iOS binary packages are x86_64 only (the arm64 slices are for devices); x86_64 apps
run in the simulator on Apple Silicon Macs too. The CI builds both as a matrix on the Intel runner, with separate
dependency caches (`ios-deps-*` and `ios-simulator-deps-*`); building all dependencies from scratch takes about
1.5 hours.

Translations are not in the git repositories of the KDE dependencies, so `build-deps.sh` also downloads their
release tarballs from download.kde.org and installs the compiled catalogs (`.mo` from `po/`, `.qm` from `poqm/`)
into the prefix. `build-app.sh` copies those and the app's own catalogs into `itinerary.app/locale/` (only for the
languages the app is translated to), where KI18n and ECM's Qt translation loader find them on iOS through the app's
data locations (patches for KI18n and ECM). The country data of iso-codes (`iso_3166-1.json`, `iso_3166-2.json`)
used by KI18n's locale data is bundled in `itinerary.app/iso-codes/json/` the same way.

`build-app.sh` sets the bundle identifier (`at.blechert.trinity`) and the name on the home
screen (`Trinity`); both can be overridden with `ITINERARY_IOS_BUNDLE_IDENTIFIER` and
`ITINERARY_IOS_DISPLAY_NAME`. The Info.plist is `src/app/ios/Info.plist.in`.

The bundle is not signed (signing is done by the publishing account, see "Publishing"). For running it from Xcode,
configuring with `-G Xcode` instead of Ninja should work too, as Qt recommends for iOS apps; that is untested.

### What is built differently on iOS

- No D-Bus, KDBusService, KWindowSystem, QApplication or the desktop style: like on Android the app uses
  QGuiApplication with the Breeze Qt Quick Controls style (qqc2-breeze-style, built with KIconThemes and
  KWidgetsAddons), see the `IOS` branches in `CMakeLists.txt` and `Q_OS_IOS` in the code.
- Everything is static: the runtime dependencies (Kirigami, Prison, ...) are linked explicitly, the QML plugins
  are found by Qt's QML import scanner (`qt_finalize_target()`; most KDE libraries needed patches to export their
  static QML plugins), and the Breeze icons are compiled into the app as resources
  (`kirigami_package_breeze_icons(TARGET ...)`, added by a Kirigami patch). The QML debugging plugins and Qt
  Multimedia's FFmpeg backend are left out, the camera uses the AVFoundation backend.
- Static linking pitfalls found at runtime: QML plugins with a custom plugin class must reference the declarative type
  registration of their module (`qml_register_types_<uri>`), otherwise the C++ types (`QML_ELEMENT`) are dropped by
  the linker ("... is not a type"); patched in KGuiAddons, KCoreAddons, KContacts, KCalendarCore, KNotifications,
  KOpeningHours, KPublicTransport and KOSMIndoorMap. Global helper types of different QML plugins can clash
  (`PlatformForeign` in KPublicTransport and KOSMIndoorMap). Kirigami's platform theme plugin of the Breeze style
  (`org.kde.breeze`) has to be linked by the app, and KIconThemes needed to learn where a static Kirigami keeps its
  icon theme.
- Disabled, as the libraries aren't built for iOS: Matrix location sharing (libQuotient, olm), the health
  certificate manager (KHealthCertificate), MapLibre maps (maplibre-native-qt), Solid. KCrash is built but not
  used (there is no crash handler on iOS), the calendar import plugin is Android only.
- PDF import is removed for licensing reasons, see below.
- No QProcess on iOS: KItinerary extracts in the app's process, the notification settings open the app's page
  in the system settings. KSandbox and KUser are not available either (the latter was used to preselect the
  ticket of the user by name).
- Screen brightness for showing barcodes uses UIScreen (`solidextras/iosbrightnessbackend.mm`).
- Files shared with the app (pkpass, ics, json) arrive as file URLs at `QDesktopServices` and are imported.

### Open issues

- Only tested in the simulator so far: the welcome page and the main page start, with icons, the Breeze style,
  German translations and the country data. Nothing was clicked through yet, the smoke test can't interact with the
  app (that would need an XCUITest runner).
- Qt translations (`.qm`, e.g. Kirigami's) are not loaded by the libraries: ECM's translation loader is a separate
  object file in the static libraries that nothing references, so the linker drops it (none of the catalog names
  is in the binary). The app loads the bundled catalogs itself on iOS (`loadBundledQtTranslations()` in
  `main.cpp`). Gettext catalogs (KI18n, most of the app's and the libraries' texts) work.
- KUser is available on iOS now (KCoreAddons patch), but the preselection of the user's ticket by name stays
  disabled on iOS: the user name of an iOS app is the sandbox's ("Mobile User"), never the traveler's.
- The window extends below the status bar and the home indicator (`Qt.ExpandedClientAreaHint` in `Main.qml`), Kirigami
  adds the safe area margins to the header and the navigation bar. Not checked yet: pages without a header, e.g.
  the barcode scanner.
- Resources of static libraries that are not referenced from code (e.g. Qt resources in KOSMIndoorMap's
  helper libraries) may need explicit `Q_INIT_RESOURCE` calls.
- App icons (asset catalog), privacy manifest and the remaining App Store metadata are still missing, see
  "App metadata". The launch screen is Qt's default one (compiled by `build-app.sh`, as Ninja only copies it).
- Notifications: KNotifications has no iOS backend yet.
- Opening documents and walking directions in other apps use the generic desktop code paths, see the table below.
  Opening an attached document with `QDesktopServices` now ends up in the import, as file URLs are handled by it.
- LGPL relinking requirement with a static app, see "Licensing".

## Testing in the simulator

`tools/ios/simulator-smoke-test.sh <app> <output dir>` boots a regular iPhone simulator of the newest iOS runtime
(about 6 minutes on the CI runner for a new simulator), installs the app and starts it twice: freshly installed (welcome page), and with the welcome page marked as shown in its settings and German as
language (`LANGUAGE=de`, main page). It fails if the app doesn't run anymore after 30 seconds, and stores screenshots,
the console output of the app (Qt logs to stderr with `QT_FORCE_STDERR_LOGGING=1`), its system log, crash reports and
a sample of its stacks (simulated apps are host processes, so `sample` works on them, e.g. to see where they hang).
The location permission is granted beforehand and a location is set: the app asks for the permission right away, and
without a location starting the app took about 20 seconds longer.

Locally, `xcrun simctl launch --console-pty booted at.blechert.trinity` shows the app's output.
The settings of the app (QSettings) are in the user defaults of the app on iOS, they can be changed with
`xcrun simctl spawn booted defaults write <app data container>/Library/Preferences/org.kde.itinerary <key> <value>`.

## Prerequisites

- A Mac with a current Xcode. iOS apps cannot be built, signed or uploaded from Linux.
- Qt 6.11 for iOS (Qt online installer or self-built). Qt Positioning, Qt Location, Qt Multimedia (barcode scanner) are needed.
- An Apple Developer Program membership for signing and App Store distribution. Uploading happens from the
  account that owns the App Store listing; see "Publishing" below.
- A real iPhone for testing (camera, location, file import), the simulator is not enough.

## Building the dependency stack

Everything Itinerary depends on has to be cross-compiled for iOS (arm64, and the simulator architecture for development).
This is done for arm64 devices by `tools/ios/build-deps.sh`, see `tools/ios/deps.txt` for what is built; the
original plan: Order roughly as the Android build log shows, see `tools/android/build-apk.sh deps`:

| Group | Packages | Notes |
|---|---|---|
| Base libraries | zlib, libxml2, libical, openssl (or Apple's Security framework via Qt), zxing-cpp, qrencode, libdmtx, olm | plain CMake/autotools builds with the iOS toolchain |
| KDE Frameworks | extra-cmake-modules, kcoreaddons, ki18n, kconfig, kirigami, kitemmodels, kholidays, karchive, prison, kunitconversion, kcontacts, kcalendarcore, kmime, kcodecs, kcolorscheme, kguiaddons, kiconthemes, knotifications, kcrash | Kirigami has worked on iOS before; knotifications needs an iOS backend (see below) |
| KDE libraries | kirigami-addons, kpublictransport, kosmindoormap, kpkpass, kitinerary, khealthcertificate, kopeninghours | kitinerary can be built without Poppler, see "Licensing" |
| Third party | qtkeychain, qcoro, libquotient, maplibre-native-qt | qtkeychain supports iOS; Matrix integration (libquotient, olm) could be disabled for a first version |
| ki18n | needs libintl | use [libintl-lite with plural form support](https://github.com/j-jorge/libintl-lite/pull/13), like the Android build |

Options worth evaluating before doing this by hand:
- KDE Craft has macOS support; check its current state for iOS targets.
- A single CMake superbuild with `CMAKE_SYSTEM_NAME=iOS` using Qt's `qt-cmake` toolchain.

## Platform specific code

Android specific code is behind `Q_OS_ANDROID`. Each of these needs an iOS counterpart, or has to be disabled:

| Area | Android implementation | iOS counterpart |
|---|---|---|
| Opening files from other apps (pkpass, PDF, ics, json) | `src/app/android/Activity.java`, `intenthandler.cpp`, `importcontroller.cpp` | done: `CFBundleDocumentTypes` in Info.plist, `QDesktopServices::setUrlHandler` for file URLs in `main.cpp` (untested) |
| File names of shared files | `filehelper.cpp` (content:// URIs) | security-scoped bookmark URLs |
| Calendar import | `src/calendarextras/` Android plugin | disabled for now; EventKit plugin (new) |
| Screen brightness for barcode scanning | `solidextras/androidbrightnessbackend` | done: `solidextras/iosbrightnessbackend.mm` (UIScreen) |
| Keeping the screen on | KGuiAddons `SystemInhibitor` | `UIApplication.idleTimerDisabled` |
| Notifications (delays, platform changes) | KNotifications Android backend | `UNUserNotificationCenter` backend for KNotifications (new) |
| Walking directions to a stop | `NavigationController::walkTo()`: Organic Maps `om://`, Google Maps `google.navigation:`, `geo:` | Organic Maps `om://route?...`, Google Maps `comgooglemaps://?daddr=LAT,LON&directionsmode=walking`, Apple Maps `maps://?daddr=LAT,LON&dirflg=w`; needs `LSApplicationQueriesSchemes` |
| Time zones | `localizer.cpp` Java fallback | not needed, Qt uses CoreFoundation on Apple platforms |
| Location permission | `QLocationPermission` (Qt, cross-platform) | works, needs `NSLocationWhenInUseUsageDescription` |
| Back navigation | Android back gesture fix in the manifest | not applicable, iOS uses the header back button and edge swipe |
| Apple Wallet passes | pkpass files open in Itinerary | on iOS they open in Apple Wallet by default; Itinerary can be offered via the share sheet ("Open in") |

## App metadata

The Info.plist with the permissions and document types used is [`src/app/ios/Info.plist.in`](../../src/app/ios/Info.plist.in). Besides that:

- Bundle identifier and app name: must belong to the publishing developer account. The name must not be
  "KDE Itinerary" (KDE trademark), and it should be clear the app is based on, but not made by, KDE.
- App icon set and launch screen storyboard.
- Privacy manifest (`PrivacyInfo.xcprivacy`) and App Store privacy labels: location (only when used),
  camera (barcode scanning), network requests to public transport data providers, no tracking.
- Public transport data providers: check the terms of the APIs used by KPublicTransport, some require keys
  that are registered to KDE.

## PDF import is removed on iOS, for licensing reasons only

Decision: the iOS version is built without Poppler, so it can't import PDF tickets. Poppler is GPL licensed, and
distributing GPL code through Apple's App Store is widely considered incompatible with the App Store terms. That is
the only reason for this. PDF import works fine technically and stays enabled on all other platforms; Apple Wallet
passes, barcodes and the other import paths are available on iOS.

## Licensing

- Itinerary and the KDE libraries are LGPL. LGPL code in a statically linked app requires that users can relink
  the app with modified libraries. For the unsigned builds attached to the GitHub releases this is the case: the app
  itself is free software, and its complete source and the scripts building it and all dependencies are in this
  repository, so it can be rebuilt with modified libraries.
- Qt is used under LGPLv3 with the same requirement. Only LGPL modules are linked into the app (Core, Gui, Quick,
  Qml, Location, Positioning, Multimedia, Network, Svg, WebSockets, ...); Qt Shader Tools (GPL) is only used while
  building Kirigami, to compile its shaders.
- For the App Store this still needs to be resolved, as its terms add restrictions of their own.
- Poppler (PDF ticket extraction in kitinerary) is GPL, which is why PDF import is removed on iOS, see above.
- KDE e.V. publishes some apps in Apple's App Store (e.g. KDE Connect), they may be able to advise.

## Publishing

For each release tag, the CI adds the unsigned app for devices to the GitHub release as `trinity-ios-unsigned.ipa`
(for a release made before that, run the workflow by hand with the tag as `release`). It has to be signed before it
can be installed, e.g. with a development certificate and provisioning profile for its bundle identifier
(`at.blechert.trinity`, or another one after re-signing).

App Store uploads have to be signed with a distribution certificate and provisioning profile of the account
that publishes the app, so a finished binary can't be signed by someone else in advance. Workable setups:

1. The account holder adds the developer to their team in App Store Connect (role "Developer" or "App Manager"),
   who then builds, signs and uploads from Xcode under that team.
2. The developer provides an Xcode archive, the account holder signs and uploads it from Xcode's Organizer.

TestFlight should be used for testing on real devices before submitting for review.
