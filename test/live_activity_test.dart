import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_activity_kit/live_activity_kit.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePlatform extends LiveActivityPlatform with MockPlatformInterfaceMixin {
  final List<Map<String, Object?>> shown = [];
  final List<Map<String, Object?>> updated = [];
  final List<Map<String, Object?>> ended = [];
  bool endedAll = false;

  LiveActivitySupport supportInfo = const LiveActivitySupport(
    isSupported: true,
    areActivitiesEnabled: true,
    supportsDynamicIsland: true,
    systemVersion: '17.4',
  );

  /// The most recent layout, decoded — the shape the widget extension sees.
  Map<String, Object?> layoutOf(Map<String, Object?> request) =>
      jsonDecode(request['layout']! as String) as Map<String, Object?>;

  @override
  Future<LiveActivitySupport> checkSupport() async => supportInfo;

  @override
  Future<LiveActivityHandle> show(Map<String, Object?> request) async {
    shown.add(request);
    return LiveActivityHandle(
      id: request['id']! as String,
      activityId: 'activity-${shown.length}',
      state: LiveActivityState.active,
    );
  }

  @override
  Future<void> update(Map<String, Object?> request) async => updated.add(request);

  @override
  Future<void> end(Map<String, Object?> request) async => ended.add(request);

  @override
  Future<void> endAll({bool immediate = false}) async => endedAll = true;

  @override
  Future<List<LiveActivityHandle>> activities() async => const [];

  @override
  Future<LiveActivityHandle?> activity(String id) async => null;

  @override
  Future<String?> pushToStartToken() async => 'abc123';

  @override
  Future<void> writeSharedJson(String key, String json) async {}

  @override
  Future<String?> readSharedJson(String key) async => null;

  @override
  Stream<LiveActivityStateChange> get states => const Stream.empty();

  @override
  Stream<LiveActivityPushToken> get pushTokens => const Stream.empty();

  @override
  Stream<String> get pushToStartTokens => const Stream.empty();

  @override
  Stream<String> get deepLinks => const Stream.empty();

  @override
  Stream<String> get sharedStoreChanges => const Stream.empty();
}

void main() {
  late _FakePlatform platform;

  setUp(() {
    platform = _FakePlatform();
    LiveActivityPlatform.instance = platform;
    LiveActivity.resetCache();
  });

  group('show', () {
    test('serializes the layout as a JSON string', () async {
      final handle = await LiveActivity.show(
        id: 'meal',
        compact: LA.text('🍱 1:00'),
        lockScreen: LA.column([LA.text('Next meal'), LA.progress(0.65)]),
      );

      expect(handle.id, 'meal');
      expect(handle.state, LiveActivityState.active);

      final request = platform.shown.single;
      expect(request['id'], 'meal');
      expect(request['layout'], isA<String>());

      final regions = platform.layoutOf(request)['regions']! as Map;
      expect(regions.keys, containsAll(['lockScreen', 'compactTrailing']));
    });

    test('rejects a layout with no regions', () {
      expect(
        () => LiveActivity.show(id: 'empty'),
        throwsA(isA<LiveActivityException>()
            .having((e) => e.code, 'code', 'invalid_argument')),
      );
    });

    test('rejects a payload over the ActivityKit limit', () {
      expect(
        () => LiveActivity.show(
          id: 'huge',
          lockScreen: LA.text('x' * (LiveActivity.maxPayloadBytes + 1)),
        ),
        throwsA(isA<LiveActivityException>()
            .having((e) => e.code, 'code', 'payload_too_large')),
      );
    });

    test('passes alert, stale date and relevance through', () async {
      await LiveActivity.show(
        id: 'order',
        lockScreen: LA.text('Preparing'),
        alert: const LiveActivityAlert(title: 'Order', body: 'On its way'),
        staleAfter: const Duration(minutes: 30),
        relevanceScore: 50,
        enablePush: true,
      );

      final request = platform.shown.single;
      expect((request['alert']! as Map)['title'], 'Order');
      expect(request['staleAt'], isA<double>());
      expect(request['relevance'], 50);
      expect(request['enablePush'], isTrue);
    });
  });

  group('update', () {
    test('merges into the layout that was shown', () async {
      await LiveActivity.show(
        id: 'meal',
        compact: LA.text('🍱 1:00'),
        lockScreen: LA.text('Lunch'),
      );

      await LiveActivity.update(id: 'meal', lockScreen: LA.text('Dinner'));

      final regions =
          platform.layoutOf(platform.updated.single)['regions']! as Map;
      expect((regions['lockScreen']! as Map)['value'], 'Dinner');
      // The compact region was not re-declared but must not disappear.
      expect((regions['compactTrailing']! as Map)['value'], '🍱 1:00');
    });

    test('merge: false drops regions the caller omitted', () async {
      await LiveActivity.show(
        id: 'meal',
        compact: LA.text('🍱'),
        lockScreen: LA.text('Lunch'),
      );

      await LiveActivity.update(
        id: 'meal',
        lockScreen: LA.text('Dinner'),
        merge: false,
      );

      final regions =
          platform.layoutOf(platform.updated.single)['regions']! as Map;
      expect(regions.keys, ['lockScreen']);
    });

    test('an update with no prior show still sends what it was given', () async {
      await LiveActivity.update(id: 'restored', lockScreen: LA.text('hi'));
      expect(platform.updated, hasLength(1));
    });
  });

  group('end', () {
    test('sends a final frame built on the last layout', () async {
      await LiveActivity.show(
        id: 'run',
        compact: LA.text('🏃'),
        lockScreen: LA.text('Running'),
      );

      await LiveActivity.end(
        id: 'run',
        lockScreen: LA.text('Workout complete'),
        policy: LiveActivityEndPolicy.after(DateTime.utc(2030)),
      );

      final request = platform.ended.single;
      expect(request['id'], 'run');
      expect((request['policy']! as Map)['dismissal'], 'after');

      final regions = platform.layoutOf(request)['regions']! as Map;
      expect((regions['lockScreen']! as Map)['value'], 'Workout complete');
      expect(regions.containsKey('compactTrailing'), isTrue);
    });

    test('omits the layout when no final content is supplied', () async {
      await LiveActivity.show(id: 'run', lockScreen: LA.text('Running'));
      await LiveActivity.end(id: 'run');

      expect(platform.ended.single.containsKey('layout'), isFalse);
    });

    test('forgets the cached layout so a later show starts clean', () async {
      await LiveActivity.show(id: 'run', lockScreen: LA.text('Running'));
      await LiveActivity.end(id: 'run');
      expect(LiveActivity.cachedLayout('run'), isNull);
    });
  });

  test('endAll clears every cached layout', () async {
    await LiveActivity.show(id: 'a', lockScreen: LA.text('a'));
    await LiveActivity.show(id: 'b', lockScreen: LA.text('b'));

    await LiveActivity.endAll();

    expect(platform.endedAll, isTrue);
    expect(LiveActivity.cachedLayout('a'), isNull);
    expect(LiveActivity.cachedLayout('b'), isNull);
  });

  group('support', () {
    test('is cached until refreshed', () async {
      expect((await LiveActivity.support()).canStart, isTrue);

      platform.supportInfo = const LiveActivitySupport(
        isSupported: true,
        areActivitiesEnabled: false,
        supportsDynamicIsland: false,
        systemVersion: '17.4',
      );

      expect((await LiveActivity.support()).canStart, isTrue,
          reason: 'cached');
      expect((await LiveActivity.support(refresh: true)).canStart, isFalse);
    });
  });
}
