import 'dart:ui' show Color, FontWeight, TextAlign;

/// ---------------------------------------------------------------------------
/// Style primitives shared by every node in the layout tree.
///
/// The DSL deliberately accepts the familiar `dart:ui` types (`Color`,
/// `FontWeight`, `TextAlign`) so that calling code reads like Flutter code.
/// Everything is flattened to JSON primitives before it crosses the bridge.
/// ---------------------------------------------------------------------------

/// Serializes a [Color] to `#RRGGBBAA`.
///
/// Hex strings compress far better than the decimal ARGB integer inside the
/// 4 KB ActivityKit content-state budget and stay debuggable in logs.
String? encodeColor(Color? color) {
  if (color == null) return null;
  final argb = color.toARGB32();
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  final a = (argb >> 24) & 0xFF;
  final hex = '#'
      '${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';
  return a == 0xFF ? hex : '$hex${a.toRadixString(16).padLeft(2, '0')}';
}

/// Parses `#RGB`, `#RRGGBB` or `#RRGGBBAA` back into a [Color].
Color? decodeColor(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return Color(raw);
  var s = raw.toString().trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) {
    s = s.split('').map((c) => '$c$c').join();
  }
  if (s.length == 6) s = '${s}ff';
  if (s.length != 8) return null;
  final value = int.tryParse(s, radix: 16);
  if (value == null) return null;
  // #RRGGBBAA -> 0xAARRGGBB
  final rgb = value >> 8;
  final a = value & 0xFF;
  return Color((a << 24) | rgb);
}

/// Maps a Flutter [FontWeight] onto the nine SwiftUI `Font.Weight` steps.
String? encodeFontWeight(FontWeight? weight) {
  if (weight == null) return null;
  return switch (weight.value) {
    100 => 'ultraLight',
    200 => 'thin',
    300 => 'light',
    400 => 'regular',
    500 => 'medium',
    600 => 'semibold',
    700 => 'bold',
    800 => 'heavy',
    _ => 'black',
  };
}

FontWeight? decodeFontWeight(Object? raw) {
  if (raw == null) return null;
  return switch (raw.toString()) {
    'ultraLight' => FontWeight.w100,
    'thin' => FontWeight.w200,
    'light' => FontWeight.w300,
    'regular' => FontWeight.w400,
    'medium' => FontWeight.w500,
    'semibold' => FontWeight.w600,
    'bold' => FontWeight.w700,
    'heavy' => FontWeight.w800,
    'black' => FontWeight.w900,
    _ => null,
  };
}

String? encodeTextAlign(TextAlign? align) {
  if (align == null) return null;
  return switch (align) {
    TextAlign.left || TextAlign.start => 'leading',
    TextAlign.right || TextAlign.end => 'trailing',
    TextAlign.center => 'center',
    TextAlign.justify => 'leading',
  };
}

TextAlign? decodeTextAlign(Object? raw) => switch (raw?.toString()) {
      'leading' => TextAlign.left,
      'trailing' => TextAlign.right,
      'center' => TextAlign.center,
      _ => null,
    };

/// Cross-axis alignment for [LARow] / [LAColumn].
enum LAAlign {
  start,
  center,
  end,
  /// Rows only: align children on their text baseline.
  baseline;

  static LAAlign? fromName(Object? raw) {
    for (final v in LAAlign.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// Main-axis distribution. SwiftUI stacks have no `MainAxisAlignment`, so the
/// renderer emulates these by inserting `Spacer()`s.
enum LADistribution {
  start,
  center,
  end,
  spaceBetween,
  spaceAround;

  static LADistribution? fromName(Object? raw) {
    for (final v in LADistribution.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// Where an image comes from.
enum LAImageSource {
  /// An SF Symbol name, e.g. `figure.run`. Zero-cost — no file transfer.
  systemName,

  /// A Flutter asset key. `setup` copies assets into the shared App Group
  /// container so the extension can read them.
  asset,

  /// A remote URL. Cached on disk in the App Group container.
  network,

  /// A file path inside the shared App Group container.
  file;

  static LAImageSource? fromName(Object? raw) {
    for (final v in LAImageSource.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// Rendering style for [LACountdown].
enum LACountdownStyle {
  /// `12:34` — counts down/up, updated by the system without a payload push.
  timer,

  /// `in 42 min`
  relative,

  /// `1:00 PM`
  time,

  /// `4:20` with a fixed leading offset, useful for stopwatch UIs.
  offset;

  static LACountdownStyle? fromName(Object? raw) {
    for (final v in LACountdownStyle.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// Insets used by [LAPadding] and [LAContainer].
class LAInsets {
  const LAInsets({
    this.top = 0,
    this.left = 0,
    this.bottom = 0,
    this.right = 0,
  });

  const LAInsets.all(double value)
      : top = value,
        left = value,
        bottom = value,
        right = value;

  const LAInsets.symmetric({double horizontal = 0, double vertical = 0})
      : top = vertical,
        bottom = vertical,
        left = horizontal,
        right = horizontal;

  final double top;
  final double left;
  final double bottom;
  final double right;

  bool get isZero => top == 0 && left == 0 && bottom == 0 && right == 0;

  /// Serialized as a 4-element array `[top, left, bottom, right]` — roughly
  /// half the bytes of an object with named keys.
  List<double> toJson() => [top, left, bottom, right];

  static LAInsets? fromJson(Object? raw) {
    if (raw is num) return LAInsets.all(raw.toDouble());
    if (raw is List && raw.length == 4) {
      return LAInsets(
        top: (raw[0] as num).toDouble(),
        left: (raw[1] as num).toDouble(),
        bottom: (raw[2] as num).toDouble(),
        right: (raw[3] as num).toDouble(),
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is LAInsets &&
      other.top == top &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right;

  @override
  int get hashCode => Object.hash(top, left, bottom, right);
}
