import 'package:flutter/material.dart';

/// Every demo exposes the same three verbs so `main.dart` can drive them all
/// through one UI: start, push an update, end.
abstract class LiveActivityDemo {
  String get id;
  String get title;
  String get description;
  IconData get icon;
  Color get accent;

  Future<void> start();

  /// One step forward — the demos model progress as an internal counter so a
  /// tap simulates whatever a real app would get from GPS, a socket, or a
  /// timer.
  Future<void> update();

  Future<void> end();

  /// Resets internal state so the demo can be started again cleanly.
  void reset() {}
}
