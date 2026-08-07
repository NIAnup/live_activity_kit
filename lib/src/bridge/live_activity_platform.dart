import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models/activity.dart';

/// Platform boundary.
///
/// The shipped implementation is [MethodChannelLiveActivity]. Tests (and any
/// future platform that grows a Live-Activity equivalent) can swap in their own
/// via [LiveActivityPlatform.instance].
abstract class LiveActivityPlatform extends PlatformInterface {
  LiveActivityPlatform() : super(token: _token);

  static final Object _token = Object();
  static LiveActivityPlatform _instance = MethodChannelLiveActivity();

  static LiveActivityPlatform get instance => _instance;

  static set instance(LiveActivityPlatform value) {
    PlatformInterface.verifyToken(value, _token);
    _instance = value;
  }

  Future<LiveActivitySupport> checkSupport();

  Future<LiveActivityHandle> show(Map<String, Object?> request);

  Future<void> update(Map<String, Object?> request);

  Future<void> end(Map<String, Object?> request);

  Future<void> endAll({bool immediate = false});

  Future<List<LiveActivityHandle>> activities();

  Future<LiveActivityHandle?> activity(String id);

  /// iOS 17.2+ push-to-start token. `null` on earlier systems.
  Future<String?> pushToStartToken();

  Future<void> writeSharedJson(String key, String json);

  Future<String?> readSharedJson(String key);

  Stream<LiveActivityStateChange> get states;

  Stream<LiveActivityPushToken> get pushTokens;

  Stream<String> get pushToStartTokens;

  Stream<String> get deepLinks;

  /// Fires when any process writes to the shared App Group store.
  Stream<String> get sharedStoreChanges;
}

/// `MethodChannel` + `EventChannel` implementation.
///
/// A Pigeon definition lives in `pigeons/live_activity_api.dart` for teams that
/// prefer generated, type-checked bindings; the hand-written channel below is
/// what the package ships so that `flutter pub get` never requires a codegen
/// step. Both speak the same wire format.
class MethodChannelLiveActivity extends LiveActivityPlatform {
  @visibleForTesting
  final MethodChannel methodChannel =
      const MethodChannel('live_activity_kit');

  @visibleForTesting
  final EventChannel eventChannel =
      const EventChannel('live_activity_kit/events');

  Stream<Map<String, Object?>>? _events;

  Stream<Map<String, Object?>> get _eventStream => _events ??= eventChannel
      .receiveBroadcastStream()
      .map((event) => (event as Map).cast<String, Object?>())
      .asBroadcastStream();

  Future<T> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await methodChannel.invokeMethod<T>(method, arguments) as T;
    } on PlatformException catch (e) {
      throw LiveActivityException(
        e.code,
        e.message ?? 'Live Activity call "$method" failed',
        details: e.details,
      );
    } on MissingPluginException {
      throw const LiveActivityException(
        'unsupported',
        'live_activity_kit is only implemented on iOS 16.1+',
      );
    }
  }

  @override
  Future<LiveActivitySupport> checkSupport() async {
    try {
      final raw = await _invoke<Map<Object?, Object?>>('checkSupport');
      return LiveActivitySupport.fromJson(raw.cast<String, Object?>());
    } on LiveActivityException catch (e) {
      if (e.code == 'unsupported') return LiveActivitySupport.unsupported;
      rethrow;
    }
  }

  @override
  Future<LiveActivityHandle> show(Map<String, Object?> request) async {
    final raw = await _invoke<Map<Object?, Object?>>('show', request);
    return LiveActivityHandle.fromJson(raw.cast<String, Object?>());
  }

  @override
  Future<void> update(Map<String, Object?> request) =>
      _invoke<void>('update', request);

  @override
  Future<void> end(Map<String, Object?> request) =>
      _invoke<void>('end', request);

  @override
  Future<void> endAll({bool immediate = false}) =>
      _invoke<void>('endAll', {'immediate': immediate});

  @override
  Future<List<LiveActivityHandle>> activities() async {
    final raw = await _invoke<List<Object?>>('activities');
    return raw
        .map((e) => LiveActivityHandle.fromJson(
            (e as Map).cast<String, Object?>()))
        .toList(growable: false);
  }

  @override
  Future<LiveActivityHandle?> activity(String id) async {
    final raw =
        await methodChannel.invokeMethod<Map<Object?, Object?>>('activity', {
      'id': id,
    });
    return raw == null
        ? null
        : LiveActivityHandle.fromJson(raw.cast<String, Object?>());
  }

  @override
  Future<String?> pushToStartToken() =>
      methodChannel.invokeMethod<String>('pushToStartToken');

  @override
  Future<void> writeSharedJson(String key, String json) =>
      _invoke<void>('storeWrite', {'key': key, 'value': json});

  @override
  Future<String?> readSharedJson(String key) =>
      methodChannel.invokeMethod<String>('storeRead', {'key': key});

  Stream<Map<String, Object?>> _of(String type) =>
      _eventStream.where((e) => e['type'] == type);

  @override
  Stream<LiveActivityStateChange> get states =>
      _of('state').map(LiveActivityStateChange.fromJson);

  @override
  Stream<LiveActivityPushToken> get pushTokens =>
      _of('pushToken').map(LiveActivityPushToken.fromJson);

  @override
  Stream<String> get pushToStartTokens =>
      _of('pushToStartToken').map((e) => e['token']?.toString() ?? '');

  @override
  Stream<String> get deepLinks =>
      _of('deepLink').map((e) => e['url']?.toString() ?? '');

  @override
  Stream<String> get sharedStoreChanges =>
      _of('store').map((e) => e['key']?.toString() ?? '');
}
