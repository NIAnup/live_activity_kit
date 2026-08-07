import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_activity_kit/live_activity_kit.dart';

/// Round-trip fidelity is the contract the SwiftUI renderer depends on: if a
/// node cannot survive `toJson -> fromJson`, it cannot survive the channel.
void main() {
  group('serialization', () {
    test('text carries every style it was given', () {
      final node = LA.text(
        'Lunch',
        size: 20,
        weight: FontWeight.bold,
        color: const Color(0xFF34C759),
        align: TextAlign.center,
        maxLines: 2,
        opacity: 0.8,
        italic: true,
        monospacedDigit: true,
      );

      final json = node.toJson();
      expect(json['type'], 'text');
      expect(json['value'], 'Lunch');
      expect(json['size'], 20);
      expect(json['weight'], 'bold');
      expect(json['color'], '#34c759');
      expect(json['align'], 'center');
      expect(json['maxLines'], 2);
      expect(json['italic'], true);
      expect(json['mono'], true);

      expect(LANode.fromJson(json), node);
    });

    test('null properties are omitted entirely', () {
      final json = LA.text('hi').toJson();
      expect(json.keys, ['type', 'value']);
    });

    test('uppercase is applied at decode time, not encode time', () {
      // The raw string stays in the payload so the renderer owns the transform;
      // this keeps the JSON diffable against the caller's source.
      final json = LA.text('live', uppercase: true).toJson();
      expect(json['value'], 'live');
      expect(json['uppercase'], true);
    });

    test('nested trees round-trip', () {
      final tree = LA.column([
        LA.row([
          LA.text('Next meal', weight: FontWeight.bold),
          LA.spacer(),
          LA.text('LIVE', size: 11, color: const Color(0xFFFF3B30)),
        ], spacing: 4),
        LA.text('Lunch - 1:00 PM', size: 20),
        LA.progress(0.65, tint: const Color(0xFF34C759), label: '65%'),
        LA.divider(),
        LA.row([
          LA.metric('42', label: 'minutes', symbol: 'clock'),
          LA.metric('420', label: 'kcal', unit: 'cal'),
        ], distribution: LADistribution.spaceBetween),
      ], spacing: 6);

      final decoded = LANode.fromJson(
        jsonDecode(jsonEncode(tree.toJson())) as Map<String, Object?>,
      );
      expect(decoded, tree);
    });

    test('every component type has a decoder', () {
      final nodes = <LANode>[
        LA.text('t'),
        LA.symbol('figure.run'),
        LA.asset('assets/a.png', width: 40, height: 40, cornerRadius: 8),
        LA.networkImage('https://example.com/a.png'),
        LA.row(const []),
        LA.column(const []),
        LA.progress(0.5),
        LA.circularProgress(0.5, center: LA.text('50')),
        LA.metric('1'),
        LA.countdown(DateTime.utc(2030)),
        LA.spacer(minLength: 4),
        LA.divider(vertical: true),
        LA.padding(LA.text('p'), all: 8),
        LA.container(
          child: LA.text('c'),
          gradient: const [Color(0xFF000000), Color(0xFFFFFFFF)],
          cornerRadius: 12,
          padding: const LAInsets.symmetric(horizontal: 8),
        ),
      ];

      for (final node in nodes) {
        expect(LANode.fromJson(node.toJson()), node, reason: node.type);
      }
    });

    test('unknown node types fail loudly', () {
      expect(
        () => LANode.fromJson({'type': 'webview'}),
        throwsA(isA<LANodeDecodeException>()),
      );
    });
  });

  group('colors', () {
    test('opaque colors drop the alpha byte', () {
      expect(LA.text('x', color: const Color(0xFF112233)).toJson()['color'],
          '#112233');
    });

    test('translucent colors keep it', () {
      expect(LA.text('x', color: const Color(0x80112233)).toJson()['color'],
          '#11223380');
    });

    test('alpha survives the round trip', () {
      final node = LA.text('x', color: const Color(0x80112233));
      final decoded = LANode.fromJson(node.toJson()) as LAText;
      expect(decoded.color!.toARGB32(), 0x80112233);
    });
  });

  group('countdown', () {
    test('encodes as epoch seconds', () {
      final until = DateTime.utc(2030, 1, 1, 12);
      final json = LA.countdown(until).toJson();
      expect(json['until'], until.millisecondsSinceEpoch / 1000.0);
      expect(json.containsKey('style'), isFalse, reason: 'timer is the default');
    });

    test('decodes back to the same instant', () {
      final until = DateTime.utc(2030, 5, 6, 7, 8, 9);
      final decoded = LANode.fromJson(LA.countdown(until).toJson()) as LACountdown;
      expect(decoded.until.toUtc(), until);
    });
  });

  group('payload size', () {
    test('a realistic tree stays well under the 4 KiB ActivityKit limit', () {
      final layout = LiveActivityLayout(
        lockScreen: LA.column([
          LA.row([LA.text('Order #1042', weight: FontWeight.bold), LA.spacer()]),
          LA.text('Out for delivery', size: 18),
          LA.progress(0.7),
          LA.row([
            LA.metric('12', label: 'min away'),
            LA.metric('2.4', label: 'km', unit: 'km'),
          ]),
        ]),
        compact: LA.text('🛵 12m'),
        minimal: LA.symbol('bicycle'),
      );

      final bytes = utf8.encode(jsonEncode(layout.toJson())).length;
      expect(bytes, lessThan(LiveActivity.maxPayloadBytes ~/ 2));
    });
  });
}
