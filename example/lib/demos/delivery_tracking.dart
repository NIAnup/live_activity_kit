import 'package:flutter/material.dart';
import 'package:live_activity_kit/live_activity_kit.dart';

import 'demo.dart';

/// Delivery tracking — the "server owns the truth" shape.
///
/// Real deliveries change while the app is closed, so this is the demo that
/// asks for a push token: `enablePush: true` makes ActivityKit issue an APNs
/// token, and the backend pushes each stage. The buttons here stand in for
/// what the server would send.
class DeliveryTrackingDemo implements LiveActivityDemo {
  DeliveryTrackingDemo({this.onPushToken});

  /// Where a real app would ship the token to its backend.
  final void Function(String token)? onPushToken;

  @override
  final String id = 'delivery';

  @override
  final String title = 'Delivery tracking';

  @override
  final String description =
      'Requests an APNs token — the stages below are what your server would push.';

  @override
  final IconData icon = Icons.delivery_dining;

  @override
  final Color accent = const Color(0xFF0A84FF);

  static const _stages = [
    ('Order confirmed', 'Restaurant is preparing your food', 'checkmark.circle.fill', 22),
    ('Being prepared', 'Kitchen is cooking', 'flame.fill', 16),
    ('Picked up', 'Sam is on the way', 'bicycle', 9),
    ('Nearby', 'Arriving in a moment', 'mappin.and.ellipse', 2),
  ];

  int _stage = 0;

  String get _statusTitle => _stages[_stage].$1;
  String get _statusBody => _stages[_stage].$2;
  String get _symbol => _stages[_stage].$3;
  DateTime get _eta => DateTime.now().add(Duration(minutes: _stages[_stage].$4));
  double get _progress => (_stage + 1) / _stages.length;

  @override
  Future<void> start() async {
    final handle = await LiveActivity.show(
      id: id,
      theme: LATheme(
        backgroundGradient: const [Color(0xFF06214A), Color(0xFF0B0B0F)],
        tint: accent,
        foreground: Colors.white,
      ),
      deepLink: 'liveactivitykit://order/1042',
      compactLeading: LA.symbol(_symbol, size: 14, color: accent),
      compactTrailing: LA.countdown(_eta,
          style: LACountdownStyle.relative, size: 13, color: accent),
      minimal: LA.symbol(_symbol, size: 13, color: accent),
      expandedLeading: LA.metric('#1042', label: 'order', symbol: 'bag.fill'),
      expandedTrailing: LA.metric(
        '${_stages[_stage].$4}',
        unit: 'min',
        label: 'eta',
        align: LAAlign.end,
        tint: accent,
      ),
      expandedBottom: LA.column([
        LA.text(_statusTitle, size: 15, weight: FontWeight.w600),
        LA.progress(_progress, tint: accent, height: 5),
      ], spacing: 6),
      lockScreen: _lockScreen(),
      // The whole point of this demo: let the backend drive it.
      enablePush: true,
      relevanceScore: 80,
    );

    debugPrint('Live Activity started: ${handle.activityId}');

    // The token arrives asynchronously, moments after the activity starts.
    LiveActivity.pushTokens
        .where((token) => token.id == id)
        .listen((token) => onPushToken?.call(token.token));
  }

  @override
  Future<void> update() async {
    if (_stage < _stages.length - 1) _stage++;

    await LiveActivity.update(
      id: id,
      compactLeading: LA.symbol(_symbol, size: 14, color: accent),
      compactTrailing: LA.countdown(_eta,
          style: LACountdownStyle.relative, size: 13, color: accent),
      minimal: LA.symbol(_symbol, size: 13, color: accent),
      expandedTrailing: LA.metric(
        '${_stages[_stage].$4}',
        unit: 'min',
        label: 'eta',
        align: LAAlign.end,
        tint: accent,
      ),
      expandedBottom: LA.column([
        LA.text(_statusTitle, size: 15, weight: FontWeight.w600),
        LA.progress(_progress, tint: accent, height: 5),
      ], spacing: 6),
      lockScreen: _lockScreen(),
      // Each stage is a genuine status change, so each one earns a banner.
      alert: LiveActivityAlert(title: _statusTitle, body: _statusBody),
    );
  }

  @override
  Future<void> end() => LiveActivity.end(
        id: id,
        compactLeading: LA.symbol('checkmark.circle.fill', size: 14, color: accent),
        compactTrailing: LA.text('Delivered', size: 12),
        lockScreen: LA.row([
          LA.symbol('checkmark.circle.fill', size: 22, color: accent),
          LA.column([
            LA.text('Delivered', size: 17, weight: FontWeight.bold),
            LA.text('Order #1042 · Enjoy your meal', size: 12, opacity: 0.7),
          ], spacing: 2),
        ], spacing: 10),
        // Keeps "Delivered" on the Lock Screen for a few minutes, then clears
        // it — long enough to notice, short enough not to linger.
        policy: LiveActivityEndPolicy.after(
          DateTime.now().add(const Duration(minutes: 5)),
        ),
      );

  @override
  void reset() => _stage = 0;

  LANode _lockScreen() => LA.column([
        LA.row([
          LA.symbol(_symbol, size: 14, color: accent),
          LA.text('Order #1042', size: 13, weight: FontWeight.w600),
          LA.spacer(),
          LA.countdown(_eta,
              style: LACountdownStyle.relative,
              size: 12,
              color: accent,
              prefix: 'arrives'),
        ], spacing: 6),
        LA.text(_statusTitle, size: 20, weight: FontWeight.bold),
        LA.text(_statusBody, size: 13, opacity: 0.7, maxLines: 1),
        LA.progress(_progress, tint: accent, height: 6, label: '${_stage + 1}/4'),
        LA.divider(),
        LA.row([
          LA.metric('Sam', label: 'courier', symbol: 'person.fill'),
          LA.metric('4.9', label: 'rating', symbol: 'star.fill'),
          LA.metric('2.4', unit: 'km', label: 'away', align: LAAlign.end),
        ], distribution: LADistribution.spaceBetween),
      ], spacing: 6);
}
