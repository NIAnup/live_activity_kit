// Pigeon interface definition.
//
// The package ships a hand-written MethodChannel bridge so that `pub get` never
// requires a codegen step, but the wire format below is the contract both sides
// implement. Teams that prefer generated, type-checked bindings can run:
//
//   dart run pigeon --input pigeons/live_activity_api.dart
//
// and point `LiveActivityPlatform.instance` at the generated `LiveActivityApi`.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/bridge/messages.g.dart',
  dartOptions: DartOptions(),
  swiftOut: 'ios/Classes/Messages.g.swift',
  swiftOptions: SwiftOptions(),
  dartPackageName: 'live_activity_kit',
))
/// Device capability snapshot.
class SupportInfo {
  SupportInfo({
    required this.isSupported,
    required this.areActivitiesEnabled,
    required this.supportsDynamicIsland,
    required this.systemVersion,
  });

  bool isSupported;
  bool areActivitiesEnabled;
  bool supportsDynamicIsland;
  String systemVersion;
}

/// A handle to a running activity.
class ActivityHandle {
  ActivityHandle({
    required this.id,
    required this.activityId,
    required this.state,
    this.pushToken,
  });

  String id;
  String activityId;

  /// `active` | `stale` | `ended` | `dismissed` | `unknown`
  String state;
  String? pushToken;
}

/// Banner shown when an update arrives on a locked device.
class AlertPayload {
  AlertPayload({required this.title, required this.body, this.sound});

  String title;
  String body;
  String? sound;
}

/// How to retire an activity.
class EndPolicy {
  EndPolicy({required this.dismissal, this.dismissAt});

  /// `standard` | `immediate` | `after`
  String dismissal;

  /// Seconds since epoch. Only read when [dismissal] is `after`.
  double? dismissAt;
}

/// Everything needed to start or update an activity.
class ActivityRequest {
  ActivityRequest({
    required this.id,
    required this.layout,
    this.alert,
    this.staleAt,
    this.relevance,
    this.enablePush = false,
  });

  String id;

  /// The serialized component tree — see `LiveActivityLayout.toJson`.
  ///
  /// A JSON string rather than a nested map: ActivityKit's content state is
  /// capped at 4 KiB and the Dart side owns the schema, so the native side
  /// never needs to understand a single node type.
  String layout;

  AlertPayload? alert;

  /// Seconds since epoch after which iOS should treat the content as stale.
  double? staleAt;

  /// 0–100; orders competing activities in the Dynamic Island.
  double? relevance;

  /// Request an APNs token for this activity.
  bool enablePush;
}

@HostApi()
abstract class LiveActivityApi {
  SupportInfo checkSupport();

  ActivityHandle show(ActivityRequest request);

  void update(ActivityRequest request);

  void end(String id, String? layout, EndPolicy policy);

  void endAll(bool immediate);

  List<ActivityHandle> activities();

  ActivityHandle? activity(String id);

  /// iOS 17.2+. `null` on earlier systems.
  String? pushToStartToken();

  /// App Group key/value store, shared with the widget extension.
  void storeWrite(String key, String value);

  String? storeRead(String key);
}

@FlutterApi()
abstract class LiveActivityEvents {
  /// Lifecycle transition for [id].
  void onStateChanged(String id, String state);

  /// A per-activity APNs token was issued or rotated.
  void onPushToken(String id, String token);

  /// iOS 17.2+ push-to-start token.
  void onPushToStartToken(String token);

  /// The user tapped an activity carrying a deep link.
  void onDeepLink(String url);

  /// Another process wrote to the shared store.
  void onStoreChanged(String key);
}
