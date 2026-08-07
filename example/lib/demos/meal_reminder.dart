import 'package:flutter/material.dart';
import 'package:live_activity_kit/live_activity_kit.dart';

import 'demo.dart';

/// Meal reminder — the "ambient information" shape.
///
/// Nothing here changes second to second, so the activity is started once with
/// a [LA.countdown] and then left alone: the countdown ticks by itself and the
/// app can be suspended the whole time.
class MealReminderDemo implements LiveActivityDemo {
  MealReminderDemo();

  @override
  final String id = 'meal';

  @override
  final String title = 'Meal reminder';

  @override
  final String description =
      'Started once, then left alone — the countdown ticks without any update.';

  @override
  final IconData icon = Icons.restaurant;

  @override
  final Color accent = const Color(0xFF34C759);

  static const _meals = [
    ('Lunch', 'Grilled chicken bowl', 620, 42),
    ('Snack', 'Greek yoghurt & berries', 180, 150),
    ('Dinner', 'Salmon, rice, greens', 740, 320),
  ];

  int _index = 0;

  DateTime get _serveAt =>
      DateTime.now().add(Duration(minutes: _meals[_index].$4));

  double get _dayProgress => (_index + 1) / (_meals.length + 1);

  @override
  Future<void> start() => LiveActivity.show(
        id: id,
        theme: LATheme(
          background: const Color(0xFF0B1F14),
          tint: accent,
          foreground: Colors.white,
        ),
        // Collapsed island: an emoji and the time. Two glyphs is all the
        // trailing slot can hold without truncating.
        compactLeading: LA.text('🍱'),
        compactTrailing: LA.countdown(_serveAt, size: 13, color: accent),
        minimal: LA.text('🍱'),
        // Expanded island: leading/trailing columns plus a full-width bottom.
        expandedLeading: LA.metric(
          _meals[_index].$1,
          label: 'next meal',
          symbol: 'fork.knife',
          tint: accent,
        ),
        expandedTrailing: LA.metric(
          '${_meals[_index].$3}',
          unit: 'kcal',
          label: 'planned',
          align: LAAlign.end,
        ),
        expandedBottom: LA.column([
          LA.text(_meals[_index].$2, size: 15),
          LA.progress(_dayProgress, tint: accent, height: 5),
        ], spacing: 6),
        lockScreen: _lockScreen(),
      );

  @override
  Future<void> update() async {
    _index = (_index + 1) % _meals.length;
    await LiveActivity.update(
      id: id,
      compactTrailing: LA.countdown(_serveAt, size: 13, color: accent),
      expandedLeading: LA.metric(
        _meals[_index].$1,
        label: 'next meal',
        symbol: 'fork.knife',
        tint: accent,
      ),
      expandedTrailing: LA.metric(
        '${_meals[_index].$3}',
        unit: 'kcal',
        label: 'planned',
        align: LAAlign.end,
      ),
      expandedBottom: LA.column([
        LA.text(_meals[_index].$2, size: 15),
        LA.progress(_dayProgress, tint: accent, height: 5),
      ], spacing: 6),
      lockScreen: _lockScreen(),
      // A meal change is worth a banner; a countdown tick would not be.
      alert: LiveActivityAlert(
        title: 'Up next: ${_meals[_index].$1}',
        body: _meals[_index].$2,
      ),
    );
  }

  @override
  Future<void> end() => LiveActivity.end(
        id: id,
        lockScreen: LA.row([
          LA.symbol('checkmark.circle.fill', size: 18, color: accent),
          LA.text('All meals logged', size: 16, weight: FontWeight.w600),
        ], spacing: 8),
        compactTrailing: LA.symbol('checkmark', color: accent),
        policy: const LiveActivityEndPolicy.standard(),
      );

  @override
  void reset() => _index = 0;

  LANode _lockScreen() => LA.column([
        LA.row([
          LA.symbol('fork.knife', size: 13, color: accent),
          LA.text('Next meal',
              size: 13, weight: FontWeight.w600, color: accent),
          LA.spacer(),
          LA.text('${_meals[_index].$3} kcal', size: 12, opacity: 0.7),
        ], spacing: 6),
        LA.text(_meals[_index].$1, size: 24, weight: FontWeight.bold),
        LA.text(_meals[_index].$2, size: 14, opacity: 0.75, maxLines: 1),
        LA.progress(_dayProgress, tint: accent, height: 6),
        LA.row([
          LA.countdown(_serveAt,
              style: LACountdownStyle.relative, size: 13, prefix: 'in'),
          LA.spacer(),
          LA.countdown(_serveAt, style: LACountdownStyle.time, size: 13),
        ]),
      ], spacing: 6);
}
