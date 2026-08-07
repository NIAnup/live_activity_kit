# live_activity_kit

Build iOS **Live Activities** and **Dynamic Island** experiences entirely from Dart.

Apple does not let Flutter render inside a Live Activity — the UI has to be SwiftUI, in a
widget extension, in a separate process. `live_activity_kit` closes that gap: you declare
the UI with a Flutter-like component DSL, the package ships it across as a compact JSON
layout tree, and a bundled recursive SwiftUI renderer draws it.

```
Dart DSL  →  JSON layout tree  →  MethodChannel  →  ActivityKit  →  SwiftUI renderer
```

One package, any use case: meals, workouts, deliveries, orders, timers, reminders,
meditation, trips, water intake — the component system is not tied to a domain.

```dart
await LiveActivity.show(
  id: 'meal',
  compact: LA.text('🍱 1:00'),
  expanded: LA.column([
    LA.text('Next meal', weight: FontWeight.bold),
    LA.text('Lunch — 1:00 PM'),
    LA.progress(0.65),
  ]),
  lockScreen: LA.column([
    LA.row([
      LA.text('Next meal', weight: FontWeight.bold),
      LA.spacer(),
      LA.text('LIVE', size: 11, color: Colors.red),
    ]),
    LA.text('Lunch — 1:00 PM', size: 20),
    LA.progress(0.65),
    LA.row([
      LA.text('In 42 min'),
      LA.spacer(),
      LA.text('420 kcal'),
    ]),
  ]),
);
```

---

## Features

- **Flutter-first API** — `show` / `update` / `end`, no Swift required.
- **Component DSL** — 12 composable components covering the shapes Live Activities allow.
- **Every region** — lock screen, compact leading/trailing, minimal, and all four
  expanded Dynamic Island regions, each with its own tree.
- **Self-updating timers** — `LA.countdown` uses SwiftUI's system-driven date text, so a
  ticking clock costs zero updates and zero battery.
- **Multiple simultaneous activities**, keyed by your own ids.
- **Push updates** — per-activity APNs tokens and iOS 17.2+ push-to-start tokens.
- **App Group store** — shared key/value and file storage between app and extension.
- **Deep links** — tap handling delivered back to Dart as a stream.
- **Images** — SF Symbols, Flutter assets, and network images (pre-cached automatically).
- **Setup automation** — `dart run live_activity_kit:setup` creates the widget extension,
  entitlements, App Group and Xcode target.
- **Safe by construction** — payloads are size-checked against ActivityKit's 4 KiB limit
  in Dart, with an error that names the activity.

---

## Requirements

| | |
|---|---|
| iOS | 16.1+ (Dynamic Island: iPhone 14 Pro and later) |
| Xcode | 15+ |
| Flutter | 3.27+ |
| Device | Live Activities do **not** run in the iOS simulator on iOS 16 |

Android and other platforms are no-ops: every call throws
`LiveActivityException('unsupported', …)`, and `LiveActivity.support()` reports
`isSupported: false`, so a single codebase ships fine.

---

## Installation

```yaml
dependencies:
  live_activity_kit: ^0.1.0
```

Then run the setup command from your app directory:

```bash
dart run live_activity_kit:setup
```

It will:

1. Create `ios/LiveActivityKitWidget/` with the widget extension and the SwiftUI renderer.
2. Derive an App Group (`group.<your.bundle.id>.liveactivity`) and write it into
   `Runner.entitlements`, the extension's entitlements, and both `Info.plist`s.
3. Add `NSSupportsLiveActivities` to `ios/Runner/Info.plist`.
4. Register the widget extension target in `Runner.xcodeproj`, embed it in the app, and
   set its build settings and bundle identifier.

Options:

```bash
dart run live_activity_kit:setup \
  --app-group=group.com.acme.app.liveactivity \  # custom App Group
  --target-name=AcmeWidget \                     # custom extension name
  --deployment-target=16.1 \
  --frequent-updates \                           # NSSupportsLiveActivitiesFrequentUpdates
  --force                                        # overwrite edited widget sources
  --no-xcode                                     # write files, skip project changes
```

### What setup cannot do

Three steps need a human, and no script can do them for you:

1. **Provisioning.** App Groups are a *signing* capability. The group has to exist on your
   Apple Developer account and be attached to both bundle identifiers. Open
   `ios/Runner.xcworkspace`, select each target → *Signing & Capabilities* → **+ App
   Groups** → tick your group. Xcode creates it on first use; this requires an
   authenticated Apple ID session, which a CLI does not have.
2. **Development team.** If `Runner` has no `DEVELOPMENT_TEAM`, set it on both targets.
3. **One build from Xcode.** `flutter run` builds the extension too, but the first Xcode
   build is what materialises provisioning profiles for the new target.

If the Xcode step fails (usually because the `xcodeproj` Ruby gem is missing — it ships
with CocoaPods), the command prints the exact manual steps and exits non-zero.

---

## Quick start

```dart
import 'package:live_activity_kit/live_activity_kit.dart';

// 1. Check the device and the user's settings.
final support = await LiveActivity.support();
if (!support.canStart) return;

// 2. Start.
final handle = await LiveActivity.show(
  id: 'order-1042',
  compactLeading: LA.symbol('bicycle'),
  compactTrailing: LA.countdown(eta, style: LACountdownStyle.relative),
  lockScreen: LA.column([
    LA.text('Out for delivery', size: 20, weight: FontWeight.bold),
    LA.progress(0.7, tint: Colors.blue),
  ], spacing: 6),
);

// 3. Update — regions you omit keep their previous content.
await LiveActivity.update(
  id: 'order-1042',
  lockScreen: LA.text('Arriving now', size: 20),
  alert: const LiveActivityAlert(title: 'Almost there', body: 'Your order is nearby'),
);

// 4. End, leaving a final frame on the Lock Screen.
await LiveActivity.end(
  id: 'order-1042',
  lockScreen: LA.text('Delivered ✓', size: 20),
);
```

---

## Components

Every component is a `LA.*` factory returning an immutable `LANode`.

| Component | Purpose |
|---|---|
| `LA.text` | Text, emoji, any Unicode SwiftUI can draw |
| `LA.image` / `LA.symbol` / `LA.asset` / `LA.networkImage` | SF Symbols, Flutter assets, remote images |
| `LA.row` | Horizontal stack (`HStack`) |
| `LA.column` | Vertical stack (`VStack`) |
| `LA.progress` | Linear progress bar with optional caption |
| `LA.circularProgress` | Progress ring with an optional centred node |
| `LA.metric` | Value + unit + label + icon — for stat rows |
| `LA.countdown` / `LA.stopwatch` | System-driven timer; **no updates needed** |
| `LA.spacer` | Flexible space |
| `LA.divider` | Hairline rule |
| `LA.padding` | Insets |
| `LA.container` | Background, gradient, corner radius, border, fixed size |

Shared styling:

```dart
LA.text(
  'Lunch',
  size: 20,
  weight: FontWeight.bold,       // dart:ui FontWeight
  color: Colors.green,           // dart:ui Color
  align: TextAlign.center,       // dart:ui TextAlign
  maxLines: 2,
  opacity: 0.8,
  italic: true,
  monospacedDigit: true,         // stops digits jittering as they change
  uppercase: true,
);

LA.row(
  [...],
  spacing: 8,
  align: LAAlign.center,                     // cross axis
  distribution: LADistribution.spaceBetween, // main axis
);
```

### Timers are special

`LA.countdown` maps to SwiftUI's `Text(date, style:)`, which the **system** redraws. A
counting clock therefore needs no updates at all:

```dart
LA.countdown(meetingStart)                                  // 04:32, ticking
LA.countdown(eta, style: LACountdownStyle.relative)         // "in 12 minutes"
LA.countdown(eta, style: LACountdownStyle.time)             // "1:04 PM"
LA.stopwatch(startedAt)                                     // counts up
```

Pushing a new `LA.text('04:32')` every second instead is the single most common way to
burn through iOS's update budget. Don't.

---

## Regions

| Parameter | Where it shows |
|---|---|
| `lockScreen` | Lock Screen, banner, StandBy |
| `compactLeading` | Dynamic Island, collapsed, left of the sensor housing |
| `compactTrailing` | Dynamic Island, collapsed, right of it |
| `compact` | Shorthand for `compactTrailing` |
| `minimal` | Dynamic Island when another activity is competing — room for one glyph |
| `expandedLeading` / `expandedTrailing` / `expandedCenter` / `expandedBottom` | Expanded island |
| `expanded` | Shorthand for `expandedBottom`, ignored if another expanded region is set |

Fallbacks: `compactTrailing ← compact`, `minimal ← compactTrailing ← compact`. The
lock-screen tree is never reused for the island — it is almost always too tall.

Theme the whole activity with `LATheme`:

```dart
theme: LATheme(
  background: const Color(0xFF0B1F14),   // lock-screen tint (iOS 16.2+)
  backgroundGradient: const [Color(0xFF06214A), Color(0xFF0B0B0F)],
  tint: Colors.green,                     // island keyline glow
  foreground: Colors.white,               // default text colour
)
```

---

## Updating activities

```dart
await LiveActivity.update(
  id: 'meal',
  lockScreen: LA.text('Dinner'),   // other regions keep their trees
);

await LiveActivity.update(
  id: 'meal',
  lockScreen: LA.text('Dinner'),
  merge: false,                    // replace the layout outright
);
```

Extras:

- `alert:` shows a banner and wakes the screen. iOS rate-limits these — use them for
  genuine status changes, not for every tick.
- `staleAfter:` tells iOS when to consider the content out of date and dim it.
- `relevanceScore:` orders competing activities in the Dynamic Island.

Observing:

```dart
LiveActivity.states.listen((change) => print('${change.id} → ${change.state.name}'));
LiveActivity.deepLinks.listen(router.go);
final running = await LiveActivity.activities();
final isLive  = await LiveActivity.isRunning('meal');
```

---

## Ending activities

```dart
await LiveActivity.end(id: 'run');                                   // default window
await LiveActivity.end(id: 'run', policy: const LiveActivityEndPolicy.immediate());
await LiveActivity.end(
  id: 'run',
  lockScreen: LA.text('Workout complete'),                            // final frame
  policy: LiveActivityEndPolicy.after(DateTime.now().add(const Duration(minutes: 5))),
);
await LiveActivity.endAll(immediate: true);                           // e.g. on logout
```

With the default policy iOS keeps the final frame on the Lock Screen for up to four
hours — usually what you want for "Delivered" or "Workout complete".

---

## App Group storage

The app and the widget extension are separate processes. Anything too big for the 4 KiB
content state goes through the App Group:

```dart
await LiveActivityStore.write('order', {'id': 1042, 'items': items});
final order = await LiveActivityStore.readMap('order');

LiveActivityStore.changes.listen((key) => print('$key changed'));
LiveActivityStore.watch('order').listen((value) => print(value));
```

Changes are broadcast with a Darwin notification, the only cross-process signal available
to an app extension. On the Swift side, use `LiveActivityAppGroup` from either target.

---

## Background and push updates

See [`doc/background_and_push.md`](doc/background_and_push.md) for the full treatment.
The short version:

- **App in the foreground** — update as often as you like (about once every 1–2 s is the
  practical floor before iOS coalesces).
- **App backgrounded** — you get seconds, not minutes. Background modes, BGTaskScheduler
  and silent pushes are all unreliable for keeping an activity current.
- **App terminated** — you cannot update at all from Dart.
- **Use APNs** whenever the truth lives on a server, or the activity must stay correct for
  more than a few minutes: deliveries, sports scores, ride-hailing, flight status.
- **Use `LA.countdown`** whenever the only thing changing is time. It needs no updates in
  any of the states above.

```dart
final handle = await LiveActivity.show(id: 'order', enablePush: true, /* … */);
LiveActivity.pushTokens.listen((t) => api.registerActivityToken(t.id, t.token));

// iOS 17.2+: start an activity from the server, with the app never launched.
final startToken = await LiveActivity.pushToStartToken();
```

---

## Performance

- **Payload size** — nulls are never serialized, colors are `#RRGGBB`, insets are 4-element
  arrays. A realistic four-region layout lands around 500–900 bytes against ActivityKit's
  4096-byte ceiling, and `LiveActivity` throws `payload_too_large` before iOS can.
- **Rendering** — Swift decodes with `JSONSerialization` into dictionaries rather than
  `Codable`; for a heterogeneous, deeply optional tree redrawn every second that is
  measurably cheaper.
- **Memory** — widget extensions are jetsam-killed long before apps are. Images are
  downsampled to their display size before decoding, and network images are fetched by the
  *app*, never by the extension.
- **Frequent updates** — put anything time-based in `LA.countdown`, and push only the
  values that genuinely change. That is what makes a 1 s workout tracker viable.

---

## Limitations

This package renders a fixed component set, by design. It does **not** support:

- **Arbitrary Flutter widgets.** Apple does not permit a Flutter engine inside a widget
  extension. Nothing can change this; it is a platform constraint, not a missing feature.
- **WebView, video, canvas, or custom painters.**
- **Custom gestures.** Live Activities allow a tap (deep link) and, on iOS 17+, App
  Intent buttons. Nothing else — no drags, no scrolling.
- **Complex animations.** iOS animates content-state transitions itself; you cannot drive
  keyframes, and long or elaborate animations are dropped.
- **Arbitrary fonts.** System fonts only (custom fonts would have to be bundled into the
  extension by hand).
- **Live Activities on Android or the web.** There is no equivalent API.
- **Payloads over 4 KiB**, more than a handful of concurrent activities, or unlimited
  update frequency — all iOS budgets.

---

## FAQ

**Why can't I just use Flutter widgets?**
The Live Activity UI is rendered by a system process, out of your app, under tight memory
and CPU limits. Only WidgetKit/SwiftUI views are allowed there. Every Flutter Live
Activity package has this constraint.

**Do I have to write any Swift?**
No. `dart run live_activity_kit:setup` generates the extension and the renderer. You only
touch Swift if you want to add components of your own.

**Can I add my own component?**
Yes: add a `LANode` subclass in Dart, a case in `LANode.parse` and a view in
`LANodeRenderer.swift`, then re-run setup to sync the extension copy.

**Does it work in the simulator?**
Live Activities work in the iOS 17+ simulator. On iOS 16 they need a real device.

**Nothing appears on screen.**
Check, in order: `LiveActivity.support()` reports `canStart`; both targets have the same
App Group; `NSSupportsLiveActivities` is in `ios/Runner/Info.plist`; the widget extension
is embedded in the app; you passed at least one region.

**How many activities can I run at once?**
iOS does not document a hard number; in practice a handful. `show` throws
`too_many_activities` when the system refuses.

**Can I start an activity from a push notification?**
On iOS 17.2+, yes — see `LiveActivity.pushToStartToken()`.

**Can the user turn this off?**
Yes, per-app in Settings. `support().areActivitiesEnabled` reflects it; re-check with
`support(refresh: true)`.

---

## Example

`example/` contains four complete demos, each showing start → update → end:

| Demo | Shape it demonstrates |
|---|---|
| Meal reminder | Ambient info; started once, countdown does the rest |
| Running tracker | High-frequency updates with a system stopwatch |
| Delivery tracking | Server-driven, with APNs push tokens and per-stage alerts |
| Meeting countdown | Fire-and-forget; zero updates after start |

```bash
cd example
dart run live_activity_kit:setup
flutter run
```

---

## Testing

```bash
flutter test                 # Dart: DSL, serialization, layout, facade
```

Swift decoder and renderer tests live in `templates/ios/Tests/LANodeTests.swift`; add the
file to a unit-test target that compiles the generated widget sources and run ⌘U. The
Dart and Swift suites assert against the same JSON payloads, which is what keeps the two
halves of the schema honest.

For integration testing, drive the plugin through
`LiveActivityPlatform.instance = YourFakePlatform()` — the platform interface is public
precisely so that widget and integration tests never need a device.

---

## License

MIT — see [LICENSE](LICENSE).
