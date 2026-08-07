import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'bridge/live_activity_platform.dart';
import 'components/node.dart';
import 'models/activity.dart';
import 'models/layout.dart';

/// The public entry point.
///
/// ```dart
/// await LiveActivity.show(
///   id: 'meal',
///   compact: LA.text('🍱 1:00'),
///   lockScreen: LA.column([
///     LA.text('Next meal', weight: FontWeight.bold),
///     LA.text('Lunch — 1:00 PM', size: 20),
///     LA.progress(0.65),
///   ]),
/// );
/// ```
abstract final class LiveActivity {
  /// ActivityKit rejects a content state larger than 4 KiB. We check in Dart so
  /// the failure names the offending activity instead of surfacing as an opaque
  /// `NSCocoaErrorDomain` from the platform channel.
  static const int maxPayloadBytes = 4096;

  static LiveActivityPlatform get _platform => LiveActivityPlatform.instance;

  /// Last layout pushed per activity id, so [update] can patch single regions
  /// without the caller re-declaring the whole UI.
  static final Map<String, LiveActivityLayout> _layouts = {};

  static LiveActivitySupport? _support;

  /// Whether Live Activities can run on this device right now.
  ///
  /// Cached after the first call; pass `refresh: true` after sending the user
  /// to Settings, since they can disable activities per-app at any time.
  static Future<LiveActivitySupport> support({bool refresh = false}) async {
    if (refresh || _support == null) {
      _support = await _platform.checkSupport();
    }
    return _support!;
  }

  /// Starts a Live Activity.
  ///
  /// Supply at least one region. `compact` fills the collapsed Dynamic Island
  /// trailing slot, `expanded` the full-width bottom area of the expanded
  /// island, and `lockScreen` the banner — see [LiveActivityLayout.resolve] for
  /// the exact fallback rules.
  ///
  /// * [staleAfter] tells iOS when the content should be considered out of
  ///   date; it dims the activity rather than showing a stale number.
  /// * [relevanceScore] orders competing activities in the Dynamic Island.
  /// * [enablePush] requests an APNs token; listen on [pushTokens].
  ///
  /// Throws [LiveActivityException] when activities are unsupported or the user
  /// has switched them off — check [support] first if you want to branch
  /// instead of catching.
  static Future<LiveActivityHandle> show({
    required String id,
    LANode? lockScreen,
    LANode? compact,
    LANode? compactLeading,
    LANode? compactTrailing,
    LANode? minimal,
    LANode? expanded,
    LANode? expandedLeading,
    LANode? expandedTrailing,
    LANode? expandedCenter,
    LANode? expandedBottom,
    LATheme theme = const LATheme(),
    String? deepLink,
    LiveActivityAlert? alert,
    Duration? staleAfter,
    double? relevanceScore,
    bool enablePush = false,
  }) async {
    final layout = LiveActivityLayout(
      lockScreen: lockScreen,
      compact: compact,
      compactLeading: compactLeading,
      compactTrailing: compactTrailing,
      minimal: minimal,
      expanded: expanded,
      expandedLeading: expandedLeading,
      expandedTrailing: expandedTrailing,
      expandedCenter: expandedCenter,
      expandedBottom: expandedBottom,
      theme: theme,
      deepLink: deepLink,
    );
    return showLayout(
      id: id,
      layout: layout,
      alert: alert,
      staleAfter: staleAfter,
      relevanceScore: relevanceScore,
      enablePush: enablePush,
    );
  }

  /// [show] for callers that already hold a [LiveActivityLayout] — useful when
  /// the UI is built by a factory or restored from disk.
  static Future<LiveActivityHandle> showLayout({
    required String id,
    required LiveActivityLayout layout,
    LiveActivityAlert? alert,
    Duration? staleAfter,
    double? relevanceScore,
    bool enablePush = false,
  }) async {
    if (layout.isEmpty) {
      throw const LiveActivityException(
        'invalid_argument',
        'A Live Activity needs at least one non-null region.',
      );
    }
    final payload = _payload(
      id: id,
      layout: layout,
      alert: alert,
      staleAfter: staleAfter,
      relevanceScore: relevanceScore,
    )..['enablePush'] = enablePush;

    final handle = await _platform.show(payload);
    _layouts[id] = layout;
    return handle;
  }

  /// Pushes new content to a running activity.
  ///
  /// Regions you omit keep their previous trees (the layout is merged against
  /// the last one shown). Pass `merge: false` to replace the layout outright,
  /// which also clears regions you no longer supply.
  ///
  /// Attaching an [alert] wakes the screen and shows a banner — reserve it for
  /// changes the user would want interrupting them for.
  static Future<void> update({
    required String id,
    LANode? lockScreen,
    LANode? compact,
    LANode? compactLeading,
    LANode? compactTrailing,
    LANode? minimal,
    LANode? expanded,
    LANode? expandedLeading,
    LANode? expandedTrailing,
    LANode? expandedCenter,
    LANode? expandedBottom,
    LATheme? theme,
    String? deepLink,
    LiveActivityAlert? alert,
    Duration? staleAfter,
    double? relevanceScore,
    bool merge = true,
  }) {
    final incoming = LiveActivityLayout(
      lockScreen: lockScreen,
      compact: compact,
      compactLeading: compactLeading,
      compactTrailing: compactTrailing,
      minimal: minimal,
      expanded: expanded,
      expandedLeading: expandedLeading,
      expandedTrailing: expandedTrailing,
      expandedCenter: expandedCenter,
      expandedBottom: expandedBottom,
      theme: theme ?? const LATheme(),
      deepLink: deepLink,
    );
    final previous = _layouts[id];
    final layout = merge && previous != null
        ? previous.copyWith(
            lockScreen: lockScreen,
            compact: compact,
            compactLeading: compactLeading,
            compactTrailing: compactTrailing,
            minimal: minimal,
            expanded: expanded,
            expandedLeading: expandedLeading,
            expandedTrailing: expandedTrailing,
            expandedCenter: expandedCenter,
            expandedBottom: expandedBottom,
            theme: theme,
            deepLink: deepLink,
          )
        : incoming;

    return updateLayout(
      id: id,
      layout: layout,
      alert: alert,
      staleAfter: staleAfter,
      relevanceScore: relevanceScore,
    );
  }

  /// [update] with a prebuilt layout. Always replaces; no merging.
  static Future<void> updateLayout({
    required String id,
    required LiveActivityLayout layout,
    LiveActivityAlert? alert,
    Duration? staleAfter,
    double? relevanceScore,
  }) async {
    await _platform.update(_payload(
      id: id,
      layout: layout,
      alert: alert,
      staleAfter: staleAfter,
      relevanceScore: relevanceScore,
    ));
    _layouts[id] = layout;
  }

  /// Ends an activity, optionally showing a final frame first.
  ///
  /// With the default [LiveActivityEndPolicy.standard] iOS keeps that final
  /// frame on the Lock Screen for up to four hours, which is usually what you
  /// want for "Delivered" or "Workout complete".
  static Future<void> end({
    required String id,
    LANode? lockScreen,
    LANode? compact,
    LANode? compactLeading,
    LANode? compactTrailing,
    LANode? minimal,
    LANode? expanded,
    LANode? expandedLeading,
    LANode? expandedTrailing,
    LANode? expandedCenter,
    LANode? expandedBottom,
    LATheme? theme,
    LiveActivityEndPolicy policy = const LiveActivityEndPolicy.standard(),
  }) async {
    final hasFinalContent = lockScreen != null ||
        compact != null ||
        compactLeading != null ||
        compactTrailing != null ||
        minimal != null ||
        expanded != null ||
        expandedLeading != null ||
        expandedTrailing != null ||
        expandedCenter != null ||
        expandedBottom != null;

    LiveActivityLayout? finalLayout;
    if (hasFinalContent) {
      final previous = _layouts[id] ?? const LiveActivityLayout();
      finalLayout = previous.copyWith(
        lockScreen: lockScreen,
        compact: compact,
        compactLeading: compactLeading,
        compactTrailing: compactTrailing,
        minimal: minimal,
        expanded: expanded,
        expandedLeading: expandedLeading,
        expandedTrailing: expandedTrailing,
        expandedCenter: expandedCenter,
        expandedBottom: expandedBottom,
        theme: theme,
      );
    }

    await _platform.end({
      'id': id,
      if (finalLayout != null) 'layout': _encode(id, finalLayout),
      'policy': policy.toJson(),
    });
    _layouts.remove(id);
  }

  /// Ends every activity this app started. Handy on logout.
  static Future<void> endAll({bool immediate = false}) async {
    await _platform.endAll(immediate: immediate);
    _layouts.clear();
  }

  /// Every activity ActivityKit currently knows about, including ones started
  /// before the app was relaunched.
  static Future<List<LiveActivityHandle>> activities() => _platform.activities();

  /// A single activity, or `null` if it is not running.
  static Future<LiveActivityHandle?> activity(String id) =>
      _platform.activity(id);

  /// `true` when an activity with [id] is currently active.
  static Future<bool> isRunning(String id) async {
    final handle = await activity(id);
    return handle != null && handle.state == LiveActivityState.active;
  }

  /// The iOS 17.2+ push-to-start token, used to *begin* an activity remotely.
  /// `null` on iOS 16.x–17.1.
  static Future<String?> pushToStartToken() => _platform.pushToStartToken();

  /// Lifecycle transitions for every activity.
  static Stream<LiveActivityStateChange> get states => _platform.states;

  /// APNs tokens as ActivityKit issues and rotates them. Send each one to your
  /// server; a token is valid only for the activity it belongs to.
  static Stream<LiveActivityPushToken> get pushTokens => _platform.pushTokens;

  /// Push-to-start tokens (iOS 17.2+). Re-issued when the app is reinstalled.
  static Stream<String> get pushToStartTokens => _platform.pushToStartTokens;

  /// Deep links from taps on an activity, as configured by
  /// [LiveActivityLayout.deepLink].
  static Stream<String> get deepLinks => _platform.deepLinks;

  /// Reads back the layout last pushed for [id], if this isolate pushed it.
  @visibleForTesting
  static LiveActivityLayout? cachedLayout(String id) => _layouts[id];

  /// Clears the in-memory layout cache. Tests only.
  @visibleForTesting
  static void resetCache() {
    _layouts.clear();
    _support = null;
  }

  static Map<String, Object?> _payload({
    required String id,
    required LiveActivityLayout layout,
    LiveActivityAlert? alert,
    Duration? staleAfter,
    double? relevanceScore,
  }) =>
      {
        'id': id,
        'layout': _encode(id, layout),
        if (alert != null) 'alert': alert.toJson(),
        if (staleAfter != null)
          'staleAt': DateTime.now().add(staleAfter).millisecondsSinceEpoch /
              1000.0,
        if (relevanceScore != null) 'relevance': relevanceScore,
      };

  /// Serializes the layout and enforces the ActivityKit size limit.
  ///
  /// Sending the tree as a single JSON string (rather than a nested map) keeps
  /// the ContentState `Codable` on the Swift side and avoids re-encoding the
  /// structure twice as it crosses the channel.
  static String _encode(String id, LiveActivityLayout layout) {
    final json = jsonEncode(layout.toJson());
    final bytes = utf8.encode(json).length;
    if (bytes > maxPayloadBytes) {
      throw LiveActivityException(
        'payload_too_large',
        'Live Activity "$id" serialized to $bytes bytes; iOS allows at most '
            '$maxPayloadBytes. Shorten text, drop network images, or move '
            'per-frame values into LA.countdown so the system animates them.',
        details: bytes,
      );
    }
    return json;
  }
}
