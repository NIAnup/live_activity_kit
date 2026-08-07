# Background updates and push

Live Activities look like they run continuously. They do not — your *app* does not run
continuously, and every update you send from Dart requires your process to be alive. This
document is about what actually works in each state, and when to move updates to a server.

---

## 1. What "app alive" buys you

| App state | Can you call `LiveActivity.update`? | Practical limit |
|---|---|---|
| Foreground | Yes | ~1 update/second before iOS coalesces them |
| Background, briefly (a few seconds after backgrounding) | Yes | Seconds |
| Background, with an active background mode (location, audio, VoIP) | Yes | While the mode keeps you alive |
| Background, no mode | No, in practice | — |
| Suspended | No | — |
| Terminated (by the user or by jetsam) | No | — |

A running/cycling tracker works second-by-second because CoreLocation keeps the app alive,
not because Live Activities have their own background budget. Take the location updates
away and the activity freezes at whatever it last showed.

### Update budget

iOS keeps a per-app budget for Live Activity updates. Exceeding it means updates are
silently dropped or delayed — there is no error. Two mitigations, in order of value:

1. **Move time to the system.** `LA.countdown` / `LA.stopwatch` map to SwiftUI's
   `Text(date, style:)`, which the *system* redraws. A ticking clock costs zero updates,
   works while suspended, and works while terminated.
2. **Only push what changed.** `LiveActivity.update` merges into the last layout, so
   sending one region is normal and cheap.

If your app genuinely needs a high cadence, declare it:

```bash
dart run live_activity_kit:setup --frequent-updates
```

which sets `NSSupportsLiveActivitiesFrequentUpdates` in `Info.plist`. It raises the
budget; it does not remove it, and App Review does look at apps that claim it.

### Stale dates

When you cannot guarantee a timely update, say so:

```dart
await LiveActivity.update(id: 'run', staleAfter: const Duration(minutes: 1), /* … */);
```

Past the stale date iOS dims the activity, telling the user the numbers are old. A dimmed
activity is much better than a confidently wrong one.

---

## 2. Background limitations, concretely

- **BGTaskScheduler** runs minutes-to-hours after you ask, at the system's convenience.
  Fine for "refresh once in a while", useless for keeping a delivery ETA current.
- **Silent pushes** (`content-available: 1`) are throttled, coalesced, and dropped
  entirely when the user has force-quit the app or Low Power Mode is on. Do not build a
  Live Activity on them.
- **Location / audio background modes** do keep you alive, but only if your app genuinely
  needs them. Requesting a background mode purely to refresh a Live Activity is an App
  Review rejection.

The rule that follows: **if the data comes from a server, update the activity from the
server.**

---

## 3. Push-to-update

ActivityKit issues an APNs token *per activity*. Request one at start:

```dart
final handle = await LiveActivity.show(
  id: 'order-1042',
  enablePush: true,
  lockScreen: /* … */,
);

LiveActivity.pushTokens
    .where((token) => token.id == 'order-1042')
    .listen((token) => api.registerActivityToken('order-1042', token.token));
```

The token arrives asynchronously (usually within a second of `show`) and **rotates** — the
stream can emit more than once for the same activity. Always send the newest one; a stale
token silently stops working.

### What the server sends

The push must target the app's bundle id with the `.push-type.liveactivity` suffix and
carry a content state your renderer understands. The `content-state` field mirrors
`LiveActivityKitAttributes.ContentState`: a serialized layout tree plus a revision.

```
POST https://api.push.apple.com/3/device/<activity push token>

:authority: api.push.apple.com
apns-push-type: liveactivity
apns-topic: com.acme.app.push-type.liveactivity
apns-priority: 10
apns-expiration: 0
```

```json
{
  "aps": {
    "timestamp": 1735689600,
    "event": "update",
    "content-state": {
      "payload": "{\"regions\":{\"lockScreen\":{\"type\":\"text\",\"value\":\"Arriving now\"}}}",
      "revision": 7,
      "version": 1
    },
    "stale-date": 1735690200,
    "relevance-score": 80,
    "alert": {
      "title": "Almost there",
      "body": "Your order is nearby",
      "sound": "default"
    }
  }
}
```

Notes that will save you an afternoon:

- `payload` is a **JSON string**, not an object. It is the exact output of
  `jsonEncode(layout.toJson())` — generate it on the server with the same schema, or have
  the client send the layout up front and let the server substitute values.
- `revision` must change on every push. ActivityKit ignores an update whose content state
  equals the current one.
- `timestamp` is seconds since epoch and must increase; older-than-current pushes are
  discarded.
- `apns-priority: 10` delivers immediately; `5` lets iOS batch it and is the polite choice
  for frequent, non-critical updates.
- Use `"event": "end"` (with a final `content-state`, plus optional `dismissal-date`) to
  end an activity from the server.

Generating the layout server-side means your backend needs the schema. Two workable
patterns:

1. **Template on the client.** Push only values; the client rebuilds and pushes the layout
   when it is next in the foreground. Simple, but stale between launches.
2. **Schema on the server.** Port `LiveActivityLayout.toJson` to your backend language.
   It is a small, stable JSON shape — the version field exists so the extension can detect
   a payload it is too old to draw.

### Push-to-start (iOS 17.2+)

You can start an activity when the app has never been launched in this session:

```dart
final token = await LiveActivity.pushToStartToken();
LiveActivity.pushToStartTokens.listen(api.registerPushToStartToken);
```

The push is the same, with `"event": "start"` and an `attributes-type` of
`LiveActivityKitAttributes` plus an `attributes` object containing your `id`:

```json
{
  "aps": {
    "timestamp": 1735689600,
    "event": "start",
    "content-state": { "payload": "{…}", "revision": 1, "version": 1 },
    "attributes-type": "LiveActivityKitAttributes",
    "attributes": { "id": "order-1042" },
    "alert": { "title": "Order confirmed", "body": "We're preparing your food" }
  }
}
```

The push-to-start token is per app, not per activity, and is reissued on reinstall.

---

## 4. When to use APNs — a decision list

Use push when **any** of these is true:

- The data originates on a server (delivery, order, flight, score, ride).
- The activity must stay correct for longer than a few minutes of background time.
- Updates arrive irregularly and you cannot predict them.
- You want the activity to survive the user force-quitting the app.

Stay client-side when **all** of these are true:

- The app is in the foreground or holds a legitimate background mode while the activity
  runs (workouts, timers, in-app processes).
- The data is generated on-device.
- The activity's lifetime is short.

And in both cases: anything that is purely a function of time belongs in `LA.countdown`,
not in a push.

---

## 5. Debugging

- **Nothing arrives.** Check the APNs topic suffix (`.push-type.liveactivity`), that you
  are using the *activity* token and not the device token, and that `revision` changed.
- **Updates stop after a while.** You are over budget, or the activity hit its 8-hour
  cap — iOS ends every Live Activity after 8 hours of activity and removes it from the
  Lock Screen 12 hours after it starts.
- **The UI freezes at an old value.** The app was suspended. Set `staleAfter` so the user
  can tell.
- **The activity vanishes.** The user dismissed it, or the system did. Listen to
  `LiveActivity.states` and treat `dismissed` as terminal.
