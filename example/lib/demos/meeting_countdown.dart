import 'package:flutter/material.dart';
import 'package:live_activity_kit/live_activity_kit.dart';

import 'demo.dart';

/// Meeting countdown — the "fire and forget" shape.
///
/// This activity is started once and never updated. Everything that changes is
/// a countdown, and iOS ends it on its own via the dismissal date, so the app
/// can be killed the moment `show` returns and the Lock Screen stays correct.
class MeetingCountdownDemo implements LiveActivityDemo {
  MeetingCountdownDemo();

  @override
  final String id = 'meeting';

  @override
  final String title = 'Meeting countdown';

  @override
  final String description =
      'Zero updates after start — the system draws every changing value.';

  @override
  final IconData icon = Icons.event;

  @override
  final Color accent = const Color(0xFFBF5AF2);

  DateTime _startsAt = DateTime.now().add(const Duration(minutes: 15));
  Duration _length = const Duration(minutes: 30);

  @override
  Future<void> start() async {
    _startsAt = DateTime.now().add(const Duration(minutes: 15));

    await LiveActivity.show(
      id: id,
      theme: LATheme(
        background: const Color(0xFF1A0F2E),
        tint: accent,
        foreground: Colors.white,
      ),
      deepLink: 'liveactivitykit://meeting/design-review',
      compactLeading: LA.symbol('video.fill', size: 13, color: accent),
      compactTrailing: LA.countdown(_startsAt, size: 13, color: accent),
      minimal: LA.countdown(_startsAt, size: 12, color: accent),
      expandedLeading: LA.metric('Design review',
          label: 'meeting', symbol: 'calendar', tint: accent),
      expandedTrailing: LA.metric('Zoom', label: 'where', align: LAAlign.end),
      expandedCenter: LA.countdown(_startsAt,
          size: 24, weight: FontWeight.bold, color: accent),
      expandedBottom: LA.row([
        LA.text('Ana, Ben, Priya, you', size: 12, opacity: 0.7),
        LA.spacer(),
        LA.countdown(_startsAt, style: LACountdownStyle.time, size: 12),
      ]),
      lockScreen: LA.column([
        LA.row([
          LA.symbol('video.fill', size: 13, color: accent),
          LA.text('Starts in', size: 13, weight: FontWeight.w600, color: accent),
          LA.spacer(),
          LA.countdown(_startsAt, style: LACountdownStyle.time, size: 12,
              color: Colors.white70),
        ], spacing: 6),
        LA.countdown(_startsAt, size: 34, weight: FontWeight.bold),
        LA.text('Design review · Zoom', size: 14, opacity: 0.8, maxLines: 1),
        LA.divider(),
        LA.row([
          LA.metric('4', label: 'attendees', symbol: 'person.2.fill'),
          LA.metric('${_length.inMinutes}', unit: 'min', label: 'length'),
          LA.metric('Room 3', label: 'backup', align: LAAlign.end),
        ], distribution: LADistribution.spaceBetween),
      ], spacing: 6),
      // Once the meeting is over the activity has nothing left to say.
      staleAfter: const Duration(minutes: 15),
    );
  }

  /// Pushing the meeting back is the only update this demo needs — and it is
  /// user-initiated, not a timer.
  @override
  Future<void> update() async {
    _startsAt = _startsAt.add(const Duration(minutes: 10));
    _length += const Duration(minutes: 10);

    await LiveActivity.update(
      id: id,
      compactTrailing: LA.countdown(_startsAt, size: 13, color: accent),
      minimal: LA.countdown(_startsAt, size: 12, color: accent),
      expandedCenter: LA.countdown(_startsAt,
          size: 24, weight: FontWeight.bold, color: accent),
      lockScreen: LA.column([
        LA.row([
          LA.symbol('clock.badge.exclamationmark', size: 13, color: accent),
          LA.text('Pushed back', size: 13, weight: FontWeight.w600, color: accent),
          LA.spacer(),
          LA.countdown(_startsAt, style: LACountdownStyle.time, size: 12,
              color: Colors.white70),
        ], spacing: 6),
        LA.countdown(_startsAt, size: 34, weight: FontWeight.bold),
        LA.text('Design review · Zoom', size: 14, opacity: 0.8, maxLines: 1),
      ], spacing: 6),
      alert: const LiveActivityAlert(
        title: 'Design review moved',
        body: 'Pushed back by 10 minutes',
      ),
      staleAfter: const Duration(minutes: 15),
    );
  }

  @override
  Future<void> end() => LiveActivity.end(
        id: id,
        policy: const LiveActivityEndPolicy.immediate(),
      );

  @override
  void reset() {
    _startsAt = DateTime.now().add(const Duration(minutes: 15));
    _length = const Duration(minutes: 30);
  }
}
