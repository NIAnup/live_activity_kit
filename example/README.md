# live_activity_kit example

Four end-to-end Live Activity demos, each with start / update / end.

| Demo | Shape it demonstrates |
|---|---|
| **Meal reminder** | Ambient info. Started once; `LA.countdown` does the rest with no updates. |
| **Running tracker** | High-frequency updates every 2 s, with elapsed time as a system stopwatch. |
| **Delivery tracking** | Server-driven: requests an APNs token, alerts on each stage, deep link on tap. |
| **Meeting countdown** | Fire-and-forget. Zero updates after start; only a reschedule pushes. |

## Running it

```bash
flutter pub get
dart run live_activity_kit:setup    # already run once; safe to repeat
flutter run                         # iOS 16 device / iOS 17+ simulator, or Android API 26+
```

On Android the same demos post an ongoing notification (Live Updates on Android 16+).
No extra setup beyond notification permission.

On iOS, before the first run, open `ios/Runner.xcworkspace` and add the App Group capability
(`group.com.example.liveActivityKitExample.liveactivity`) to **both** the `Runner` and
`LiveActivityKitWidget` targets, and set a development team on both. Those two steps need
a signed-in Apple ID and cannot be scripted.

The app shows a support banner (OS version, whether activities / notifications are
enabled, Dynamic Island or Android Live Updates) and a live event log fed by
`LiveActivity.states`, `LiveActivity.pushTokens` and `LiveActivity.deepLinks`.

## On-device tests

```bash
flutter test integration_test -d <device id>
```
