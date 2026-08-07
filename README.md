# live_activity_kit

**Build iOS Live Activities and Dynamic Island widgets in Flutter — entirely from Dart.
No Swift, no manual Xcode setup.**

[![pub package](https://img.shields.io/pub/v/live_activity_kit.svg)](https://pub.dev/packages/live_activity_kit)
[![platform](https://img.shields.io/badge/platform-iOS%2016.1%2B-lightgrey.svg)](https://pub.dev/packages/live_activity_kit)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`live_activity_kit` is a Flutter plugin for **iOS Live Activities**, the **Dynamic
Island**, and **Lock Screen widgets**, powered by **ActivityKit** and **WidgetKit**. You
describe the UI with a Flutter-like component DSL in Dart; the package serializes it to a
compact JSON layout tree and a bundled **SwiftUI** renderer draws it inside a widget
extension it generates for you.

```
Your Dart code  →  JSON layout tree  →  MethodChannel  →  ActivityKit  →  SwiftUI renderer
```

It is **not** tied to one use case. The same components build a food delivery tracker, a
running tracker, an order status bar, a countdown timer, a meal reminder, a ride tracker,
a meditation session, or anything else you can lay out with text, images, stacks and
progress.

---

## Contents

- [Why this package](#why-this-package)
- [Quick start (5 minutes)](#quick-start-5-minutes)
- [Installation & setup](#installation--setup)
- [Recipes](#recipes) — delivery tracking, workout, countdown, order status
- [Components](#components)
- [Regions: Lock Screen & Dynamic Island](#regions-lock-screen--dynamic-island)
- [Updating & ending](#updating-and-ending-activities)
- [Push updates with APNs](#push-updates-with-apns)
- [App Group storage](#app-group-storage)
- [Performance](#performance)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

---

## Why this package

Adding a Live Activity to a Flutter app normally means leaving Flutter entirely. You have
to create a Widget Extension target by hand, write SwiftUI views, define
`ActivityAttributes`, configure an App Group, add entitlements, wire a MethodChannel, and
then keep two separate UIs in sync forever.

Apple does not allow a Flutter engine to render inside a Live Activity — the UI *must* be
SwiftUI, in a separate extension process. That constraint is not going away, so this
package absorbs it instead of fighting it:

| Doing it by hand | With `live_activity_kit` |
|---|---|
| Create the Widget Extension in Xcode | `dart run live_activity_kit:setup` |
| Write SwiftUI views per feature | Write `LA.column([...])` in Dart |
| Define `ActivityAttributes` / `ContentState` | Generated, generic, already done |
| Configure App Group + entitlements | Automated |
| Hand-roll a MethodChannel | Built in |
| Maintain Swift + Dart UI in parallel | One UI, in Dart |

You still get real SwiftUI rendering and real ActivityKit behaviour — you just never open
the Swift files.

---

## Quick start (5 minutes)

**1. Add the dependency**

```bash
flutter pub add live_activity_kit
```

**2. Generate the widget extension**

```bash
dart run live_activity_kit:setup
```

**3. Enable the App Group in Xcode** (once — it needs a signed-in Apple ID)

```
open ios/Runner.xcworkspace
Runner target                → Signing & Capabilities → + App Groups → tick your group
LiveActivityKitWidget target → Signing & Capabilities → + App Groups → tick the same group
```

**4. Start an activity from Dart**

```dart
import 'package:live_activity_kit/live_activity_kit.dart';

await LiveActivity.show(
  id: 'meal',

  // Dynamic Island, collapsed
  compact: LA.text('🍱 1:00'),

  // Dynamic Island, expanded
  expanded: LA.column([
    LA.text('Next meal', weight: FontWeight.bold),
    LA.text('Lunch — 1:00 PM'),
    LA.progress(0.65),
  ]),

  // Lock Screen banner
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

**5. Update it and end it**

```dart
await LiveActivity.update(id: 'meal', lockScreen: LA.text('Dinner — 7:30 PM', size: 20));
await LiveActivity.end(id: 'meal');
```

That's the whole API surface for most apps: `show`, `update`, `end`.

---

## Installation & setup

### Requirements

| | |
|---|---|
| **iOS** | 16.1+ (Lock Screen), iPhone 14 Pro and later for the Dynamic Island |
| **Xcode** | 15 or newer |
| **Flutter** | 3.27 or newer |
| **Device** | Real device required on iOS 16; the iOS 17+ simulator works |

Other platforms are safe no-ops: `LiveActivity.support()` reports `isSupported: false` and
calls throw `LiveActivityException('unsupported', …)`, so one codebase ships everywhere.

### What `setup` does for you

```bash
dart run live_activity_kit:setup
```

1. Creates `ios/LiveActivityKitWidget/` — the widget extension plus the SwiftUI renderer.
2. Derives an App Group (`group.<your.bundle.id>.liveactivity`) and writes it into
   `Runner.entitlements`, the extension entitlements, and both `Info.plist` files.
3. Adds `NSSupportsLiveActivities` to `ios/Runner/Info.plist`.
4. Registers the extension target in `Runner.xcodeproj`, embeds it in your app, and sets
   its bundle identifier, entitlements, deployment target and Swift version.

Re-running it is safe: generated renderer files are re-synced, and files you edited are
left alone unless you pass `--force`.

```bash
dart run live_activity_kit:setup \
  --app-group=group.com.acme.app.liveactivity \  # custom App Group id
  --target-name=AcmeWidget \                     # custom extension target name
  --deployment-target=16.1 \
  --frequent-updates \                           # NSSupportsLiveActivitiesFrequentUpdates
  --force \                                      # overwrite edited widget sources
  --no-xcode                                     # write files, don't touch the project
```

### The three steps a script cannot do

1. **Add the App Group capability** in Xcode for both targets. App Groups are a *signing*
   capability — creating one requires an authenticated Apple ID session that a CLI does
   not have.
2. **Set a development team** on both targets, if `Runner` doesn't have one.
3. **Build once from Xcode**, so provisioning profiles are materialised for the new
   target. After that, `flutter run` handles everything.

If the Xcode step fails (usually because the `xcodeproj` Ruby gem is missing — it ships
with CocoaPods), the command prints exact manual instructions and exits non-zero.

---

## Recipes

Copy-paste starting points for the most common Live Activity use cases.

### Food delivery / order tracking

```dart
await LiveActivity.show(
  id: 'order-1042',
  theme: LATheme(tint: Colors.blue, foreground: Colors.white),
  deepLink: 'myapp://order/1042',

  compactLeading: LA.symbol('bicycle'),
  compactTrailing: LA.countdown(eta, style: LACountdownStyle.relative),
  minimal: LA.symbol('bicycle'),

  lockScreen: LA.column([
    LA.row([
      LA.symbol('bicycle', size: 14, color: Colors.blue),
      LA.text('Order #1042', size: 13, weight: FontWeight.w600),
      LA.spacer(),
      LA.countdown(eta, style: LACountdownStyle.relative, prefix: 'arrives'),
    ], spacing: 6),
    LA.text('Out for delivery', size: 20, weight: FontWeight.bold),
    LA.progress(0.7, tint: Colors.blue, label: '3/4'),
  ], spacing: 6),

  enablePush: true,      // let your server drive it — see "Push updates"
  relevanceScore: 80,
);
```

### Workout / running tracker

```dart
await LiveActivity.show(
  id: 'run',
  compactLeading: LA.symbol('figure.run', color: Colors.orange),
  compactTrailing: LA.stopwatch(startedAt),        // ticks by itself, no updates

  expandedLeading: LA.metric('4.21', unit: 'km', label: 'distance'),
  expandedTrailing: LA.metric('5:12', unit: '/km', label: 'pace', align: LAAlign.end),
  expandedCenter: LA.stopwatch(startedAt, size: 22, weight: FontWeight.bold),
  expandedBottom: LA.progress(0.84, tint: Colors.orange),

  lockScreen: LA.row([
    LA.circularProgress(0.84, size: 54, lineWidth: 6, tint: Colors.orange,
        center: LA.text('84', size: 15, weight: FontWeight.bold)),
    LA.column([
      LA.stopwatch(startedAt, size: 26, weight: FontWeight.bold),
      LA.row([
        LA.metric('4.21', unit: 'km', label: 'distance'),
        LA.metric('5:12', unit: '/km', label: 'pace'),
        LA.metric('261', unit: 'kcal', label: 'burned'),
      ], distribution: LADistribution.spaceBetween),
    ], spacing: 4),
  ], spacing: 14),

  staleAfter: const Duration(minutes: 1),   // dim it if GPS stops feeding us
);
```

### Countdown timer / meeting reminder

The cheapest possible activity — started once, never updated:

```dart
await LiveActivity.show(
  id: 'meeting',
  compactLeading: LA.symbol('video.fill'),
  compactTrailing: LA.countdown(startsAt),
  lockScreen: LA.column([
    LA.text('Design review', size: 14, opacity: 0.8),
    LA.countdown(startsAt, size: 34, weight: FontWeight.bold),
  ], spacing: 4),
);
// No update() calls needed — the system redraws the clock.
```

### Order status with a final frame

```dart
await LiveActivity.update(
  id: 'order-1042',
  lockScreen: LA.text('Arriving now', size: 20, weight: FontWeight.bold),
  alert: const LiveActivityAlert(title: 'Almost there', body: 'Your order is nearby'),
);

await LiveActivity.end(
  id: 'order-1042',
  lockScreen: LA.row([
    LA.symbol('checkmark.circle.fill', size: 22, color: Colors.green),
    LA.text('Delivered', size: 17, weight: FontWeight.bold),
  ], spacing: 10),
  policy: LiveActivityEndPolicy.after(DateTime.now().add(const Duration(minutes: 5))),
);
```

The `example/` app contains all four of these as complete, runnable demos.

---

## Components

Each component is an `LA.*` factory returning an immutable `LANode`. Arbitrary Flutter
widgets are **not** supported (see [Limitations](#limitations)) — this fixed set is what
SwiftUI can render inside a Live Activity.

| Component | What it renders |
|---|---|
| `LA.text` | Text, emoji, any Unicode SwiftUI can draw |
| `LA.symbol` | An SF Symbol — zero payload cost, always instant |
| `LA.asset` | A Flutter asset (auto-copied into the App Group) |
| `LA.networkImage` | A remote image (downloaded and cached by the app, not the extension) |
| `LA.row` | Horizontal stack (SwiftUI `HStack`) |
| `LA.column` | Vertical stack (SwiftUI `VStack`) |
| `LA.progress` | Linear progress bar, optional caption |
| `LA.circularProgress` | Progress ring, optional centred node |
| `LA.metric` | Value + unit + label + icon — for stat rows |
| `LA.countdown` / `LA.stopwatch` | **Self-updating timer — needs no updates at all** |
| `LA.spacer` | Flexible space |
| `LA.divider` | Hairline rule |
| `LA.padding` | Insets around a child |
| `LA.container` | Background / gradient / corner radius / border / fixed size |

### Styling

The DSL takes the familiar `dart:ui` types, so it reads like Flutter code:

```dart
LA.text(
  'Lunch',
  size: 20,
  weight: FontWeight.bold,        // Flutter FontWeight
  color: Colors.green,            // Flutter Color
  align: TextAlign.center,        // Flutter TextAlign
  maxLines: 2,
  opacity: 0.8,
  italic: true,
  monospacedDigit: true,          // stops digits jittering as they change
  uppercase: true,
);

LA.row(
  [...],
  spacing: 8,
  align: LAAlign.center,                      // cross axis
  distribution: LADistribution.spaceBetween,  // main axis
);

LA.container(
  child: LA.text('Badge'),
  gradient: const [Color(0xFF06214A), Color(0xFF0B0B0F)],
  cornerRadius: 12,
  padding: const LAInsets.symmetric(horizontal: 8, vertical: 4),
);
```

### Timers deserve their own paragraph

`LA.countdown` maps to SwiftUI's `Text(date, style:)`, which **the system** redraws. A
counting clock therefore needs **zero** updates — it keeps ticking while your app is
suspended or even terminated:

```dart
LA.countdown(meetingStart)                             // 04:32, ticking down
LA.countdown(eta, style: LACountdownStyle.relative)    // "in 12 minutes"
LA.countdown(eta, style: LACountdownStyle.time)        // "1:04 PM"
LA.stopwatch(startedAt)                                // counts up
```

Pushing a new `LA.text('04:32')` every second instead is the single most common way apps
burn through iOS's Live Activity update budget and end up frozen. Use the countdown.

---

## Regions: Lock Screen & Dynamic Island

iOS shows your activity in several places, each with its own space. Every region takes its
own component tree.

```
COLLAPSED DYNAMIC ISLAND            MINIMAL (two activities competing)
┌───────────────────────────┐       ┌────┐        ┌────┐
│ ●compactLeading   compact │       │ ●  │  ····  │ ●  │
│                 Trailing● │       └────┘        └────┘
└───────────────────────────┘       one glyph of space

EXPANDED DYNAMIC ISLAND             LOCK SCREEN / BANNER / STANDBY
┌─────────────────────────────┐     ┌─────────────────────────────┐
│ expandedLeading   Trailing  │     │                             │
│       expandedCenter        │     │        lockScreen           │
│       expandedBottom        │     │                             │
└─────────────────────────────┘     └─────────────────────────────┘
```

| Parameter | Where it appears |
|---|---|
| `lockScreen` | Lock Screen, notification banner, StandBy |
| `compactLeading` | Collapsed island, left of the sensor housing |
| `compactTrailing` | Collapsed island, right of it |
| `compact` | Shorthand for `compactTrailing` |
| `minimal` | When another activity competes for the island — room for one glyph |
| `expandedLeading` / `expandedTrailing` / `expandedCenter` / `expandedBottom` | Expanded island |
| `expanded` | Shorthand for `expandedBottom`, ignored if you set another expanded region |

**Fallbacks:** `compactTrailing ← compact`, and `minimal ← compactTrailing ← compact`. The
lock-screen tree is deliberately never reused for the island — it is almost always too
tall and would be clipped.

### Theming

```dart
theme: LATheme(
  background: const Color(0xFF0B1F14),                            // Lock Screen tint
  backgroundGradient: const [Color(0xFF06214A), Color(0xFF0B0B0F)],
  tint: Colors.green,          // Dynamic Island keyline glow
  foreground: Colors.white,    // default text colour for the whole tree
)
```

---

## Updating and ending activities

### Update

Regions you omit keep their previous content, so a partial update is normal and cheap:

```dart
await LiveActivity.update(
  id: 'meal',
  lockScreen: LA.text('Dinner'),        // compact/expanded regions are preserved
);

await LiveActivity.update(
  id: 'meal',
  lockScreen: LA.text('Dinner'),
  merge: false,                         // replace the layout outright
);
```

Optional extras:

| Parameter | Effect |
|---|---|
| `alert:` | Shows a banner and wakes the screen. iOS rate-limits these — use for real status changes, not every tick |
| `staleAfter:` | iOS dims the activity once the content is this old |
| `relevanceScore:` | Orders competing activities in the Dynamic Island |

### End

```dart
await LiveActivity.end(id: 'run');                                        // default window
await LiveActivity.end(id: 'run', policy: const LiveActivityEndPolicy.immediate());
await LiveActivity.end(
  id: 'run',
  lockScreen: LA.text('Workout complete'),                                // final frame
  policy: LiveActivityEndPolicy.after(DateTime.now().add(const Duration(minutes: 5))),
);
await LiveActivity.endAll(immediate: true);                               // e.g. on logout
```

With the default policy iOS keeps that final frame on the Lock Screen for up to four
hours — usually exactly what you want for "Delivered" or "Workout complete".

### Observing

```dart
LiveActivity.states.listen((change) => print('${change.id} → ${change.state.name}'));
LiveActivity.deepLinks.listen(router.go);                 // taps on the activity

final running = await LiveActivity.activities();          // survives app restarts
final isLive  = await LiveActivity.isRunning('meal');
final support = await LiveActivity.support();             // canStart, supportsDynamicIsland…
```

Multiple activities run simultaneously — just give each one its own `id`.

---

## Push updates with APNs

If the data lives on a server (delivery, ride, flight, sports score), update the activity
*from* the server. Your app cannot reliably update a Live Activity while backgrounded, and
cannot update it at all once terminated.

```dart
await LiveActivity.show(id: 'order-1042', enablePush: true, /* … */);

LiveActivity.pushTokens
    .where((t) => t.id == 'order-1042')
    .listen((t) => api.registerActivityToken(t.id, t.token));   // tokens rotate — resend

// iOS 17.2+: start an activity from the server, app never launched
final startToken = await LiveActivity.pushToStartToken();
```

The APNs payload, topic format, `content-state` shape, push-to-start, and the rules about
`revision` and `timestamp` are documented in full — with working JSON — in
**[doc/background_and_push.md](doc/background_and_push.md)**.

**Rule of thumb:** anything driven by time → `LA.countdown`. Anything driven by a server →
APNs. Anything driven by the user while the app is open → `LiveActivity.update`.

---

## App Group storage

The app and the widget extension are separate processes. The layout travels inside the
4 KiB ActivityKit content state; anything bigger goes through the shared App Group:

```dart
await LiveActivityStore.write('order', {'id': 1042, 'items': items});
final order = await LiveActivityStore.readMap('order');

LiveActivityStore.changes.listen((key) => print('$key changed'));
LiveActivityStore.watch('order').listen(print);
```

Changes are broadcast with a Darwin notification — the only cross-process signal available
to an app extension. From Swift, use `LiveActivityAppGroup` in either target.

---

## Performance

Live Activities run in a memory-capped extension and redraw often, so the package is built
around that:

- **Small payloads.** Nulls are never serialized, colours are `#RRGGBB`, insets are
  4-element arrays. A realistic four-region layout is 500–900 bytes against ActivityKit's
  4096-byte ceiling — and `LiveActivity` throws `payload_too_large` in Dart, naming the
  activity, before iOS can reject it silently.
- **Fast decode.** Swift decodes with `JSONSerialization` into dictionaries rather than
  `Codable`; for a heterogeneous, deeply optional tree redrawn every second that is
  measurably cheaper.
- **Low memory.** Images are downsampled to their display size before decoding, and remote
  images are fetched by the *app*, never by the extension (which is jetsam-killed long
  before your app would be).
- **Frequent updates.** Put anything time-based in `LA.countdown` and push only values
  that genuinely change. That is what makes a 1–2 second workout tracker viable.

---

## Limitations

Read this section before you design your UI. These are platform constraints, not a backlog:

- ❌ **Arbitrary Flutter widgets.** Apple does not permit a Flutter engine inside a widget
  extension. No package can do this — the UI must be SwiftUI.
- ❌ **WebView, video, `Canvas`, `CustomPainter`.**
- ❌ **Custom gestures.** A Live Activity supports a tap (deep link) and, on iOS 17+, App
  Intent buttons. No drags, no scrolling, no swipes.
- ❌ **Complex animations.** iOS animates content-state transitions itself; you cannot
  drive keyframes, and elaborate animations are dropped.
- ❌ **Custom fonts.** System fonts only, unless you bundle fonts into the extension by hand.
- ❌ **Android / web / desktop.** No equivalent OS feature exists.
- ⚠️ **Budgets:** 4 KiB per content state, a handful of concurrent activities, a limited
  update rate, an 8-hour activity lifetime and 12-hour Lock Screen lifetime.

---

## Troubleshooting

**Nothing appears on screen.** Check in order: `LiveActivity.support()` returns
`canStart: true`; both targets have the *same* App Group ticked in Signing & Capabilities;
`NSSupportsLiveActivities` is in `ios/Runner/Info.plist`; the extension is embedded in the
app; you passed at least one region to `show`.

**`LiveActivityException(disabled)`.** The user turned Live Activities off for your app in
Settings. Re-check with `LiveActivity.support(refresh: true)`.

**`LiveActivityException(payload_too_large)`.** Your tree serialized past 4 KiB. Shorten
text, drop network images, or move per-second values into `LA.countdown`.

**`LiveActivityException(app_group_missing)`.** The App Group capability isn't attached, or
the two targets disagree. Re-run `dart run live_activity_kit:setup` and re-check Xcode.

**Updates stop after a while.** You are over iOS's update budget, or the activity hit the
8-hour cap. Move time-based values to `LA.countdown`; consider `--frequent-updates`.

**The UI freezes at an old value.** Your app was suspended. Set `staleAfter` so iOS dims
it, and move to APNs push updates.

**The widget extension won't build.** Open `ios/Runner.xcworkspace` (not `.xcodeproj`) and
confirm the `LiveActivityKitWidget` target has a development team and a deployment target
of 16.1 or higher.

---

## FAQ

**Do I have to write any Swift?**
No. `setup` generates the extension and the renderer. Swift is only involved if you choose
to add your own components.

**Can I use my existing Flutter widgets in the Live Activity?**
No — and neither can any other package. The Live Activity UI is rendered by a system
process outside your app, where only WidgetKit/SwiftUI views are allowed.

**Does it work in the simulator?**
Yes on iOS 17+. On iOS 16 you need a real device.

**Can I add my own component?**
Yes: add a `LANode` subclass in Dart, a case in `LANode.parse`, and a view in
`LANodeRenderer.swift`, then re-run setup to sync the extension's copy.

**Can I run several activities at once?**
Yes — one per `id`. iOS doesn't document a hard limit; `show` throws
`too_many_activities` when the system refuses.

**Can I start a Live Activity from a push notification?**
On iOS 17.2+, yes — `LiveActivity.pushToStartToken()`.

**Does this support Android?**
No. Live Activities are an iOS feature with no Android equivalent. Calls are safe no-ops
so your codebase stays single-source.

**How do I test without a device?**
Set `LiveActivityPlatform.instance = YourFakePlatform()`. The platform interface is public
so widget and unit tests never need hardware.

---

## Example app

`example/` contains four complete demos, each with start → update → end:

| Demo | What it demonstrates |
|---|---|
| **Meal reminder** | Ambient info; started once, `LA.countdown` does the rest |
| **Running tracker** | 2-second updates with a system stopwatch and progress ring |
| **Delivery tracking** | APNs push tokens, per-stage alerts, deep links, gradients |
| **Meeting countdown** | Fire-and-forget; zero updates after start |

```bash
cd example
dart run live_activity_kit:setup
flutter run
```

---

## Testing

```bash
flutter test                                   # DSL, JSON schema, layout, facade
cd example && flutter test integration_test    # on-device ActivityKit tests
```

Swift decoder and renderer tests live in `templates/ios/Tests/LANodeTests.swift` — add the
file to a unit-test target that compiles the generated widget sources and run ⌘U. The Dart
and Swift suites assert against the same JSON payloads, which is what keeps both halves of
the schema honest.

---

## Contributing

Issues and pull requests are welcome at
[github.com/NIAnup/live_activity_kit](https://github.com/NIAnup/live_activity_kit).

## License

MIT — see [LICENSE](LICENSE).

---

<sub>Keywords: flutter live activities, ios dynamic island flutter, activitykit flutter
plugin, flutter lock screen widget, widgetkit flutter, flutter ios widget extension,
live activity package, flutter delivery tracking ui, flutter workout live activity,
dynamic island package, flutter apns live activity push.</sub>
