import 'dart:async';
import 'dart:convert';

import '../bridge/live_activity_platform.dart';

/// Shared storage between the Flutter app and the widget extension.
///
/// The two run in separate processes with separate containers; an App Group is
/// the only supported way to hand data across. `dart run live_activity_kit:setup`
/// wires the group up for both targets.
///
/// The layout tree itself travels inside the ActivityKit content state, not
/// here — this store is for the bulk that would not fit in 4 KB: cached
/// artwork, look-up tables, user preferences the extension needs.
///
/// ```dart
/// await LiveActivityStore.write('order', {'id': 42, 'items': items});
/// LiveActivityStore.changes.listen((key) => debugPrint('$key changed'));
/// ```
abstract final class LiveActivityStore {
  static LiveActivityPlatform get _platform => LiveActivityPlatform.instance;

  /// Writes a JSON-encodable value under [key] in the App Group defaults and
  /// posts a Darwin notification so the other process can react.
  static Future<void> write(String key, Object? value) =>
      _platform.writeSharedJson(key, jsonEncode(value));

  /// Reads a value previously stored under [key].
  static Future<Object?> read(String key) async {
    final raw = await _platform.readSharedJson(key);
    return raw == null ? null : jsonDecode(raw);
  }

  /// Typed convenience for map-shaped values.
  static Future<Map<String, Object?>?> readMap(String key) async {
    final value = await read(key);
    return value is Map ? value.cast<String, Object?>() : null;
  }

  /// Removes [key].
  static Future<void> delete(String key) => _platform.writeSharedJson(key, '');

  /// Emits the key whenever *either* process writes to the shared store.
  ///
  /// Backed by `CFNotificationCenterGetDarwinNotifyCenter`, the only
  /// cross-process observation mechanism available to app extensions.
  static Stream<String> get changes => _platform.sharedStoreChanges;

  /// Watches a single key and emits its decoded value on every change.
  static Stream<Object?> watch(String key) =>
      changes.where((k) => k == key).asyncMap((_) => read(key));
}
