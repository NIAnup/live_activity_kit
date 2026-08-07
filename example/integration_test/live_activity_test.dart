import 'dart:ui' show FontWeight;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live_activity_kit/live_activity_kit.dart';

/// On-device integration tests.
///
///     cd example && flutter test integration_test -d <device id>
///
/// These exercise the real MethodChannel, ActivityKit and widget extension, so
/// they need a physical device on iOS 16 (the simulator is fine from iOS 17)
/// with the app signed and Live Activities enabled in Settings. Everything that
/// can be checked without a device — the DSL, the JSON schema, region
/// resolution, merge semantics — lives in the package's `test/` suite instead,
/// against a fake `LiveActivityPlatform`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Activities survive app restarts, so a leftover from a previous run would
    // make `activities()` assertions flaky.
    await LiveActivity.endAll(immediate: true);
  });

  tearDownAll(() async {
    await LiveActivity.endAll(immediate: true);
  });

  testWidgets('reports device support', (tester) async {
    final support = await LiveActivity.support(refresh: true);
    expect(support.isSupported, isTrue,
        reason: 'run on iOS 16.1+ with NSSupportsLiveActivities set');
    expect(support.areActivitiesEnabled, isTrue,
        reason: 'enable Live Activities for this app in Settings');
  });

  testWidgets('start, update and end a real activity', (tester) async {
    final handle = await LiveActivity.show(
      id: 'integration',
      compact: LA.text('⏱'),
      lockScreen: LA.column([
        LA.text('Integration test', weight: FontWeight.bold),
        LA.progress(0.1),
      ]),
    );

    expect(handle.activityId, isNotEmpty);
    expect(await LiveActivity.isRunning('integration'), isTrue);

    await LiveActivity.update(
      id: 'integration',
      lockScreen: LA.column([
        LA.text('Integration test', weight: FontWeight.bold),
        LA.progress(0.9),
      ]),
    );

    await LiveActivity.end(
      id: 'integration',
      policy: const LiveActivityEndPolicy.immediate(),
    );

    // `end` is asynchronous on the ActivityKit side; give the state change a
    // moment to propagate back through the event channel.
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(await LiveActivity.isRunning('integration'), isFalse);
  });

  testWidgets('runs several activities at once', (tester) async {
    await LiveActivity.show(id: 'a', lockScreen: LA.text('A'));
    await LiveActivity.show(id: 'b', lockScreen: LA.text('B'));

    final ids = (await LiveActivity.activities()).map((a) => a.id).toSet();
    expect(ids, containsAll(['a', 'b']));

    await LiveActivity.endAll(immediate: true);
  });

  testWidgets('rejects an oversized payload before reaching iOS', (tester) async {
    expect(
      () => LiveActivity.show(
        id: 'too-big',
        lockScreen: LA.text('x' * 5000),
      ),
      throwsA(isA<LiveActivityException>()
          .having((e) => e.code, 'code', 'payload_too_large')),
    );
  });

  testWidgets('App Group storage round-trips between processes', (tester) async {
    await LiveActivityStore.write('probe', {'value': 42});
    expect(await LiveActivityStore.readMap('probe'), {'value': 42});
  });
}
