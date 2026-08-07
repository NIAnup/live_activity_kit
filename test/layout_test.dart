import 'package:flutter_test/flutter_test.dart';
import 'package:live_activity_kit/live_activity_kit.dart';

void main() {
  group('region resolution', () {
    test('compact fills the trailing slot', () {
      final layout = LiveActivityLayout(compact: LA.text('🍱'));
      expect(layout.resolve(LARegion.compactTrailing), LA.text('🍱'));
      expect(layout.resolve(LARegion.compactLeading), isNull);
    });

    test('explicit compactTrailing wins over the shorthand', () {
      final layout = LiveActivityLayout(
        compact: LA.text('a'),
        compactTrailing: LA.text('b'),
      );
      expect(layout.resolve(LARegion.compactTrailing), LA.text('b'));
    });

    test('minimal falls back through compactTrailing to compact', () {
      expect(
        LiveActivityLayout(compact: LA.text('🍱')).resolve(LARegion.minimal),
        LA.text('🍱'),
      );
      expect(
        LiveActivityLayout(
          compact: LA.text('a'),
          minimal: LA.text('m'),
        ).resolve(LARegion.minimal),
        LA.text('m'),
      );
    });

    test('expanded lands in the bottom region', () {
      final layout = LiveActivityLayout(expanded: LA.text('e'));
      expect(layout.resolve(LARegion.expandedBottom), LA.text('e'));
    });

    test('expanded shorthand is ignored once a column is declared', () {
      // Mixing them would put the same tree on screen twice.
      final layout = LiveActivityLayout(
        expanded: LA.text('e'),
        expandedLeading: LA.text('l'),
      );
      expect(layout.resolve(LARegion.expandedLeading), LA.text('l'));
      expect(layout.resolve(LARegion.expandedBottom), isNull);
    });

    test('lockScreen never leaks into island regions', () {
      final layout = LiveActivityLayout(lockScreen: LA.text('tall'));
      for (final region in LARegion.values) {
        if (region == LARegion.lockScreen) continue;
        expect(layout.resolve(region), isNull, reason: region.name);
      }
    });
  });

  group('json', () {
    test('only resolved regions are emitted', () {
      final json = LiveActivityLayout(
        lockScreen: LA.text('l'),
        compact: LA.text('c'),
      ).toJson();

      final regions = (json['regions'] as Map).keys.toSet();
      expect(regions, {'lockScreen', 'compactTrailing', 'minimal'});
    });

    test('an empty theme is omitted', () {
      final json = LiveActivityLayout(lockScreen: LA.text('l')).toJson();
      expect(json.containsKey('theme'), isFalse);
    });

    test('round-trips through fromJson', () {
      final layout = LiveActivityLayout(
        lockScreen: LA.column([LA.text('a'), LA.progress(0.4)]),
        compactLeading: LA.symbol('flame'),
        compactTrailing: LA.text('12m'),
        deepLink: 'myapp://order/42',
      );

      final decoded = LiveActivityLayout.fromJson(layout.toJson());
      expect(decoded.lockScreen, layout.lockScreen);
      expect(decoded.compactLeading, layout.compactLeading);
      expect(decoded.compactTrailing, layout.compactTrailing);
      expect(decoded.deepLink, 'myapp://order/42');
    });
  });

  group('copyWith', () {
    test('keeps regions the caller did not touch', () {
      final original = LiveActivityLayout(
        lockScreen: LA.text('lock'),
        compact: LA.text('compact'),
      );
      final updated = original.copyWith(lockScreen: LA.text('new lock'));

      expect(updated.lockScreen, LA.text('new lock'));
      expect(updated.resolve(LARegion.compactTrailing), LA.text('compact'));
    });
  });

  test('isEmpty detects a layout with nothing to draw', () {
    expect(const LiveActivityLayout().isEmpty, isTrue);
    expect(LiveActivityLayout(minimal: LA.text('x')).isEmpty, isFalse);
  });
}
