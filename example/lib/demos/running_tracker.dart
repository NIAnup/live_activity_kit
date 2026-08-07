import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_activity_kit/live_activity_kit.dart';

import 'demo.dart';

/// Running tracker — the "high frequency, app in foreground" shape.
///
/// The elapsed time is *not* pushed: it is an [LA.stopwatch], which the system
/// redraws on its own. Only distance and pace actually travel over the bridge,
/// which is what keeps a once-per-second workout inside iOS's update budget.
class RunningTrackerDemo implements LiveActivityDemo {
  RunningTrackerDemo();

  @override
  final String id = 'run';

  @override
  final String title = 'Running tracker';

  @override
  final String description =
      'Ticks every 2s while running. Elapsed time is a system timer, not a push.';

  @override
  final IconData icon = Icons.directions_run;

  @override
  final Color accent = const Color(0xFFFF9F0A);

  static const _goalKm = 5.0;

  DateTime _startedAt = DateTime.now();
  double _km = 0;
  Timer? _timer;

  String get _pace {
    if (_km < 0.05) return '--:--';
    final secondsPerKm =
        DateTime.now().difference(_startedAt).inSeconds / _km;
    final minutes = secondsPerKm ~/ 60;
    final seconds = (secondsPerKm % 60).round().clamp(0, 59);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  int get _kcal => (_km * 62).round();

  @override
  Future<void> start() async {
    _startedAt = DateTime.now();
    _km = 0;

    await LiveActivity.show(
      id: id,
      theme: LATheme(tint: accent, foreground: Colors.white),
      compactLeading: LA.symbol('figure.run', size: 14, color: accent),
      compactTrailing: LA.stopwatch(_startedAt, size: 13, color: accent),
      minimal: LA.symbol('figure.run', size: 13, color: accent),
      expandedLeading: LA.metric(_km.toStringAsFixed(2),
          unit: 'km', label: 'distance', tint: accent),
      expandedTrailing: LA.metric(_pace,
          unit: '/km', label: 'pace', align: LAAlign.end),
      expandedCenter: LA.stopwatch(_startedAt, size: 22, weight: FontWeight.bold),
      expandedBottom: LA.progress(0, tint: accent, height: 5),
      lockScreen: _lockScreen(),
      // A workout that stops sending for a minute is a bug the user should see.
      staleAfter: const Duration(minutes: 1),
      relevanceScore: 100,
    );

    // A real app would drive this from CoreLocation. Two seconds is about the
    // fastest cadence worth pushing: below that iOS starts coalescing updates.
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => update());
  }

  @override
  Future<void> update() async {
    _km += 0.03;
    final progress = (_km / _goalKm).clamp(0.0, 1.0);

    await LiveActivity.update(
      id: id,
      expandedLeading: LA.metric(_km.toStringAsFixed(2),
          unit: 'km', label: 'distance', tint: accent),
      expandedTrailing: LA.metric(_pace,
          unit: '/km', label: 'pace', align: LAAlign.end),
      expandedBottom: LA.progress(progress, tint: accent, height: 5),
      lockScreen: _lockScreen(),
      staleAfter: const Duration(minutes: 1),
    );
  }

  @override
  Future<void> end() async {
    _timer?.cancel();
    _timer = null;

    await LiveActivity.end(
      id: id,
      compactLeading: LA.symbol('checkmark', size: 14, color: accent),
      compactTrailing: LA.text('${_km.toStringAsFixed(1)} km', size: 13),
      lockScreen: LA.column([
        LA.row([
          LA.symbol('flag.checkered', size: 14, color: accent),
          LA.text('Workout complete',
              size: 15, weight: FontWeight.w600, color: accent),
        ], spacing: 6),
        LA.row([
          LA.metric(_km.toStringAsFixed(2), unit: 'km', label: 'distance'),
          LA.metric(_pace, unit: '/km', label: 'avg pace'),
          LA.metric('$_kcal', unit: 'kcal', label: 'burned', align: LAAlign.end),
        ], distribution: LADistribution.spaceBetween),
      ], spacing: 8),
    );
  }

  @override
  void reset() {
    _timer?.cancel();
    _timer = null;
    _km = 0;
  }

  LANode _lockScreen() {
    final progress = (_km / _goalKm).clamp(0.0, 1.0);
    return LA.column([
      LA.row([
        LA.symbol('figure.run', size: 13, color: accent),
        LA.text('MORNING RUN',
            size: 12, weight: FontWeight.w700, color: accent, uppercase: true),
        LA.spacer(),
        LA.text('${(progress * 100).round()}% of ${_goalKm.toStringAsFixed(0)} km',
            size: 11, opacity: 0.6),
      ], spacing: 6),
      LA.row([
        LA.circularProgress(
          progress,
          size: 54,
          lineWidth: 6,
          tint: accent,
          center: LA.text('${(progress * 100).round()}',
              size: 15, weight: FontWeight.bold),
        ),
        LA.column([
          LA.stopwatch(_startedAt, size: 26, weight: FontWeight.bold),
          LA.row([
            LA.metric(_km.toStringAsFixed(2), unit: 'km', label: 'distance'),
            LA.metric(_pace, unit: '/km', label: 'pace'),
            LA.metric('$_kcal', unit: 'kcal', label: 'burned'),
          ], distribution: LADistribution.spaceBetween),
        ], spacing: 4),
      ], spacing: 14, align: LAAlign.center),
    ], spacing: 8);
  }
}
