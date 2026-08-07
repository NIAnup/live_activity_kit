# Changelog

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
