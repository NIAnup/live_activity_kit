/// Lifecycle state reported by ActivityKit.
enum LiveActivityState {
  /// Visible and updatable.
  active,

  /// Content is older than its `staleDate`; iOS may dim it.
  stale,

  /// `end()` was called; still on screen during its dismissal window.
  ended,

  /// Removed from the Lock Screen, either by the user or by the system.
  dismissed,

  unknown;

  static LiveActivityState fromName(Object? raw) {
    for (final v in LiveActivityState.values) {
      if (v.name == raw) return v;
    }
    return LiveActivityState.unknown;
  }
}

/// How iOS should retire an activity after `end()`.
enum LiveActivityDismissal {
  /// Leave the final content up for iOS's default window (up to 4 hours).
  standard,

  /// Remove it now.
  immediate,

  /// Remove it at [LiveActivityEndPolicy.dismissAt].
  after;

  static LiveActivityDismissal fromName(Object? raw) {
    for (final v in LiveActivityDismissal.values) {
      if (v.name == raw) return v;
    }
    return LiveActivityDismissal.standard;
  }
}

/// Controls the dismissal behaviour passed to `Activity.end(_:dismissalPolicy:)`.
class LiveActivityEndPolicy {
  const LiveActivityEndPolicy.standard()
      : dismissal = LiveActivityDismissal.standard,
        dismissAt = null;

  const LiveActivityEndPolicy.immediate()
      : dismissal = LiveActivityDismissal.immediate,
        dismissAt = null;

  const LiveActivityEndPolicy.after(DateTime this.dismissAt)
      : dismissal = LiveActivityDismissal.after;

  final LiveActivityDismissal dismissal;
  final DateTime? dismissAt;

  Map<String, Object?> toJson() => {
        'dismissal': dismissal.name,
        if (dismissAt != null)
          'dismissAt': dismissAt!.toUtc().millisecondsSinceEpoch / 1000.0,
      };
}

/// An alert shown when an update arrives while the device is locked.
///
/// Alerts are rate-limited by iOS; use them for genuinely notable changes
/// ("your order is out for delivery"), not for every tick.
class LiveActivityAlert {
  const LiveActivityAlert({
    required this.title,
    required this.body,
    this.sound,
  });

  final String title;
  final String body;

  /// Name of a sound file in the app bundle. `null` uses the default.
  final String? sound;

  Map<String, Object?> toJson() => {
        'title': title,
        'body': body,
        if (sound != null) 'sound': sound,
      };
}

/// A handle to a running activity.
class LiveActivityHandle {
  const LiveActivityHandle({
    required this.id,
    required this.activityId,
    required this.state,
    this.pushToken,
  });

  /// The id you passed to `LiveActivity.show`.
  final String id;

  /// ActivityKit's own identifier — the one that appears in APNs topics.
  final String activityId;

  final LiveActivityState state;

  /// Hex-encoded APNs push token for this activity, when `enablePush` was set.
  /// Arrives asynchronously; prefer `LiveActivity.pushTokens` for the stream.
  final String? pushToken;

  static LiveActivityHandle fromJson(Map<String, Object?> json) =>
      LiveActivityHandle(
        id: json['id']?.toString() ?? '',
        activityId: json['activityId']?.toString() ?? '',
        state: LiveActivityState.fromName(json['state']),
        pushToken: json['pushToken']?.toString(),
      );

  @override
  String toString() =>
      'LiveActivityHandle(id: $id, activityId: $activityId, state: ${state.name})';
}

/// Emitted by `LiveActivity.pushTokens` whenever ActivityKit rotates a token.
class LiveActivityPushToken {
  const LiveActivityPushToken({required this.id, required this.token});

  final String id;

  /// Hex string, ready to use as the APNs device token.
  final String token;

  static LiveActivityPushToken fromJson(Map<String, Object?> json) =>
      LiveActivityPushToken(
        id: json['id']?.toString() ?? '',
        token: json['token']?.toString() ?? '',
      );

  @override
  String toString() => 'LiveActivityPushToken($id, ${token.substring(0, 8)}…)';
}

/// Emitted by `LiveActivity.states` on every lifecycle transition.
class LiveActivityStateChange {
  const LiveActivityStateChange({required this.id, required this.state});

  final String id;
  final LiveActivityState state;

  static LiveActivityStateChange fromJson(Map<String, Object?> json) =>
      LiveActivityStateChange(
        id: json['id']?.toString() ?? '',
        state: LiveActivityState.fromName(json['state']),
      );

  @override
  String toString() => 'LiveActivityStateChange($id → ${state.name})';
}

/// Whether this device can run Live Activities right now.
class LiveActivitySupport {
  const LiveActivitySupport({
    required this.isSupported,
    required this.areActivitiesEnabled,
    required this.supportsDynamicIsland,
    required this.systemVersion,
  });

  /// iOS 16.1+ and the app is configured with `NSSupportsLiveActivities`.
  final bool isSupported;

  /// The user has not switched Live Activities off for your app in Settings.
  final bool areActivitiesEnabled;

  /// iPhone 14 Pro and later.
  final bool supportsDynamicIsland;

  final String systemVersion;

  /// `true` when `show()` will actually put something on screen.
  bool get canStart => isSupported && areActivitiesEnabled;

  static LiveActivitySupport fromJson(Map<String, Object?> json) =>
      LiveActivitySupport(
        isSupported: json['isSupported'] == true,
        areActivitiesEnabled: json['areActivitiesEnabled'] == true,
        supportsDynamicIsland: json['supportsDynamicIsland'] == true,
        systemVersion: json['systemVersion']?.toString() ?? '',
      );

  static const unsupported = LiveActivitySupport(
    isSupported: false,
    areActivitiesEnabled: false,
    supportsDynamicIsland: false,
    systemVersion: '',
  );

  @override
  String toString() => 'LiveActivitySupport(supported: $isSupported, '
      'enabled: $areActivitiesEnabled, island: $supportsDynamicIsland, '
      'iOS $systemVersion)';
}

/// Thrown for every failure surfaced by the native side.
class LiveActivityException implements Exception {
  const LiveActivityException(this.code, this.message, {this.details});

  /// One of: `unsupported`, `disabled`, `not_found`, `payload_too_large`,
  /// `too_many_activities`, `app_group_missing`, `invalid_argument`, `unknown`.
  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'LiveActivityException($code): $message';
}
