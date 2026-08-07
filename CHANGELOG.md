# Changelog

## 1.0.0

First release verified end-to-end on a device. Fixes four bugs that made 0.1.0
fail on a consumer's first `flutter run` — **anyone on 0.1.0 should upgrade**.

### Fixed

- **Podfile deployment target.** Flutter scaffolds `platform :ios` commented out,
  so CocoaPods assumed 12.0 and refused to resolve this pod with "requires a
  higher minimum iOS deployment version". `setup` now raises the Podfile and the
  Runner target to 13.0.
- **Build cycle.** Xcode appends "Embed Foundation Extensions" after Flutter's
  "Thin Binary" phase; both touch `Runner.app`, producing "Cycle inside Runner".
  `setup` now reorders the embed phase ahead of it.
- **Extension failed to install.** `$(FLUTTER_BUILD_NUMBER)` does not resolve for
  the widget target, so the extension shipped with no `CFBundleVersion` and iOS
  rejected it with "Failed to create app extension placeholder". `setup` now
  points the target at `Flutter/Generated.xcconfig`, keeping the extension's
  version in lockstep with the app.
- **`Text.DateStyle` availability.** Used without a guard while the pod deploys
  to iOS 13, breaking compilation with "'DateStyle' is only available in iOS
  14.0 or newer".

### Added

- Real Dynamic Island screenshot in the README, produced by the example app.
- Troubleshooting entries for each error above, plus `ld: framework 'Flutter'
  not found` (a Flutter SDK problem, fixed by `flutter precache --ios --force`).

### Verified

Dart analysis and 35 unit tests; Swift type-checked at iOS 13.0/14.0/16.1; the
generated widget extension builds; the example app builds, installs and runs on
an iOS 26 simulator; 5 on-device integration tests exercise real ActivityKit
start/update/end, concurrent activities and App Group storage.

## 0.1.0

Initial release.

- Component DSL (`LA.*`) with 12 components: text, image, row, column, progress,
  circularProgress, metric, countdown, spacer, divider, padding, container.
- All eight Live Activity regions, each with its own component tree, plus `compact` and
  `expanded` shorthands and documented fallbacks.
- Compact JSON layout schema with `fromJson`/`toJson` on every node and a 4 KiB payload
  guard that fails in Dart rather than in ActivityKit.
- `LiveActivity.show` / `update` (merging) / `end` / `endAll`, multiple simultaneous
  activities, lifecycle and deep-link streams.
- Recursive SwiftUI renderer, ActivityKit manager supporting iOS 16.1+ with 16.2 content
  API and 17.2 push-to-start where available.
- APNs push token and push-to-start token streams.
- App Group key/value and file store with cross-process change notifications.
- Automatic image prefetching for Flutter assets and network images.
- `dart run live_activity_kit:setup` — widget extension, entitlements, App Group,
  Info.plist keys and Xcode target registration.
- Example app with four end-to-end demos; Dart and Swift test suites.
