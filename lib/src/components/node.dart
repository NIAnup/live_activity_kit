import 'dart:ui' show Color, FontWeight, TextAlign;

import 'style.dart';

/// ---------------------------------------------------------------------------
/// The layout tree.
///
/// Every node is an immutable value object that serializes to a compact JSON
/// map. Nulls are never emitted: the SwiftUI renderer supplies the default for
/// any absent key, which keeps payloads well inside ActivityKit's 4 KB
/// content-state budget.
/// ---------------------------------------------------------------------------
abstract class LANode {
  const LANode();

  /// Discriminator written to the `type` key.
  String get type;

  /// Subclass hook: emit only the keys this node actually carries.
  void writeProperties(Map<String, Object?> json);

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'type': type};
    writeProperties(json);
    json.removeWhere((_, value) => value == null);
    return json;
  }

  /// Rebuilds a node (and its subtree) from decoded JSON.
  ///
  /// Throws [LANodeDecodeException] for an unknown or malformed node so that
  /// round-trip tests fail loudly instead of silently dropping UI.
  static LANode fromJson(Map<String, Object?> json) {
    final type = json['type'];
    final factory = _decoders[type];
    if (factory == null) {
      throw LANodeDecodeException('Unknown node type "$type"');
    }
    return factory(json);
  }

  static List<LANode> _children(Object? raw) => (raw as List? ?? const [])
      .map((c) => LANode.fromJson((c as Map).cast<String, Object?>()))
      .toList(growable: false);

  static LANode? _child(Object? raw) => raw == null
      ? null
      : LANode.fromJson((raw as Map).cast<String, Object?>());

  static double? _double(Object? raw) => (raw as num?)?.toDouble();

  static final Map<String, LANode Function(Map<String, Object?>)> _decoders = {
    LAText.kType: LAText.fromJson,
    LAImage.kType: LAImage.fromJson,
    LARow.kType: LARow.fromJson,
    LAColumn.kType: LAColumn.fromJson,
    LAProgress.kType: LAProgress.fromJson,
    LACircularProgress.kType: LACircularProgress.fromJson,
    LAMetric.kType: LAMetric.fromJson,
    LACountdown.kType: LACountdown.fromJson,
    LASpacer.kType: LASpacer.fromJson,
    LADivider.kType: LADivider.fromJson,
    LAPadding.kType: LAPadding.fromJson,
    LAContainer.kType: LAContainer.fromJson,
  };

  @override
  String toString() => '$runtimeType(${toJson()})';

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is LANode &&
      _deepEquals(other.toJson(), toJson());

  @override
  int get hashCode => _deepHash(toJson());
}

/// Thrown when a JSON payload cannot be turned back into a [LANode].
class LANodeDecodeException implements Exception {
  const LANodeDecodeException(this.message);
  final String message;
  @override
  String toString() => 'LANodeDecodeException: $message';
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? value) {
  if (value is Map) {
    // Order-independent so map iteration order can't change the hash.
    var hash = 0;
    for (final entry in value.entries) {
      hash ^= Object.hash(entry.key, _deepHash(entry.value));
    }
    return hash;
  }
  if (value is List) {
    return Object.hashAll(value.map(_deepHash));
  }
  return value.hashCode;
}

// ===========================================================================
// text
// ===========================================================================

class LAText extends LANode {
  const LAText(
    this.value, {
    this.size,
    this.weight,
    this.color,
    this.align,
    this.maxLines,
    this.opacity,
    this.italic = false,
    this.monospacedDigit = false,
    this.uppercase = false,
  });

  static const kType = 'text';

  /// Plain text. Emoji are fine; so is any Unicode SwiftUI can render.
  final String value;
  final double? size;
  final FontWeight? weight;
  final Color? color;
  final TextAlign? align;
  final int? maxLines;
  final double? opacity;
  final bool italic;

  /// Prevents horizontal jitter when digits change every second — the right
  /// default for timers and counters.
  final bool monospacedDigit;
  final bool uppercase;

  @override
  String get type => kType;

  @override
  void writeProperties(Map<String, Object?> json) {
    json['value'] = value;
    json['size'] = size;
    json['weight'] = encodeFontWeight(weight);
    json['color'] = encodeColor(color);
    json['align'] = encodeTextAlign(align);
    json['maxLines'] = maxLines;
    json['opacity'] = opacity;
    if (italic) json['italic'] = true;
    if (monospacedDigit) json['mono'] = true;
    if (uppercase) json['uppercase'] = true;
  }

  static LAText fromJson(Map<String, Object?> json) => LAText(
        json['value']?.toString() ?? '',
        size: LANode._double(json['size']),
        weight: decodeFontWeight(json['weight']),
        color: decodeColor(json['color']),
        align: decodeTextAlign(json['align']),
        maxLines: (json['maxLines'] as num?)?.toInt(),
        opacity: LANode._double(json['opacity']),
        italic: json['italic'] == true,
        monospacedDigit: json['mono'] == true,
        uppercase: json['uppercase'] == true,
      );
}

// ===========================================================================
// image
// ===========================================================================

class LAImage extends LANode {
  const LAImage({
    required this.source,
    required this.value,
    this.size,
    this.width,
    this.height,
    this.color,
    this.cornerRadius,
  });

  /// SF Symbol — the cheapest and most reliable image in a Live Activity.
  const LAImage.symbol(String name, {double? size, Color? color})
      : this(
          source: LAImageSource.systemName,
          value: name,
          size: size,
          color: color,
        );

  const LAImage.asset(
    String assetKey, {
    double? width,
    double? height,
    double? cornerRadius,
  }) : this(
          source: LAImageSource.asset,
          value: assetKey,
          width: width,
          height: height,
          cornerRadius: cornerRadius,
        );

  const LAImage.network(
    String url, {
    double? width,
    double? height,
    double? cornerRadius,
  }) : this(
          source: LAImageSource.network,
          value: url,
          width: width,
          height: height,
          cornerRadius: cornerRadius,
        );

  static const kType = 'image';

  final LAImageSource source;
  final String value;

  /// Point size for SF Symbols.
  final double? size;
  final double? width;
  final double? height;

  /// Tint. Applied as a template rendering mode for symbols.
  final Color? color;
  final double? cornerRadius;

  @override
  String get type => kType;

  @override
  void writeProperties(Map<String, Object?> json) {
    json['source'] = source.name;
    json['value'] = value;
    json['size'] = size;
    json['width'] = width;
    json['height'] = height;
    json['color'] = encodeColor(color);
    json['radius'] = cornerRadius;
  }

  static LAImage fromJson(Map<String, Object?> json) => LAImage(
        source: LAImageSource.fromName(json['source']) ??
            LAImageSource.systemName,
        value: json['value']?.toString() ?? '',
        size: LANode._double(json['size']),
        width: LANode._double(json['width']),
        height: LANode._double(json['height']),
        color: decodeColor(json['color']),
        cornerRadius: LANode._double(json['radius']),
      );
}

// ===========================================================================
// row / column
// ===========================================================================

class LARow extends LANode {
  const LARow(
    this.children, {
    this.spacing,
    this.align = LAAlign.center,
    this.distribution = LADistribution.start,
  });

  static const kType = 'row';

  final List<LANode> children;
  final double? spacing;
  final LAAlign align;
  final LADistribution distribution;

  @override
  String get type => kType;

  @override
  void writeProperties(Map<String, Object?> json) {
    json['children'] = children.map((c) => c.toJson()).toList();
    json['spacing'] = spacing;
    if (align != LAAlign.center) json['align'] = align.name;
    if (distribution != LADistribution.start) {
      json['distribution'] = distribution.name;
    }
  }

  static LARow fromJson(Map<String, Object?> json) => LARow(
        LANode._children(json['children']),
        spacing: LANode._double(json['spacing']),
        align: LAAlign.fromName(json['align']) ?? LAAlign.center,
        distribution: LADistribution.fromName(json['distribution']) ??
            LADistribution.start,
      );
}

class LAColumn extends LANode {
  const LAColumn(
    this.children, {
    this.spacing,
    this.align = LAAlign.start,
    this.distribution = LADistribution.start,
  });

  static const kType = 'column';

  final List<LANode> children;
  final double? spacing;
  final LAAlign align;
  final LADistribution distribution;

  @override
  String get type => kType;

  @override
  void writeProperties(Map<String, Object?> json) {
    json['children'] = children.map((c) => c.toJson()).toList();
    json['spacing'] = spacing;
    if (align != LAAlign.start) json['align'] = align.name;
    if (distribution != LADistribution.start) {
      json['distribution'] = distribution.name;
    }
  }

  static LAColumn fromJson(Map<String, Object?> json) => LAColumn(
        LANode._children(json['children']),
        spacing: LANode._double(json['spacing']),
        align: LAAlign.fromName(json['align']) ?? LAAlign.start,
        distribution: LADistribution.fromName(json['distribution']) ??
            LADistribution.start,
      );
}

// ===========================================================================
// progress
// ===========================================================================

class LAProgress extends LANode {
  const LAProgress(
    this.value, {
    this.tint,
    this.trackColor,
    this.height,
    this.cornerRadius,
    this.label,
  });

  static const kType = 'progress';

  /// 0.0 – 1.0. Values outside the range are clamped by the renderer.
  final double value;
  final Color? tint;
  final Color? trackColor;
  final double? height;
  final double? cornerRadius;

  /// Optional trailing caption, e.g. `65%`.
  final String? label;

  @override
  String get type => kType;

  @override
  void writeProperties(Map<String, Object?> json) {
    json['value'] = value;
    json['tint'] = encodeColor(tint);
    json['track'] = encodeColor(trackColor);
    json['height'] = height;
    json['radius'] = cornerRadius;
    json['label'] = label;
  }

  static LAProgress fromJson(Map<String, Object?> json) => LAProgress(
        LANode._double(json['value']) ?? 0,
        tint: decodeColor(json['tint']),
        trackColor: decodeColor(json['track']),
        height: LANode._double(json['height']),
        cornerRadius: LANode._double(json['radius']),
        label: json['label']?.toString(),
      );
}

class LACircularProgress extends LANode {
  const LACircularProgress(
    this.value, {
    this.size,
    this.lineWidth,
    this.tint,
    this.trackColor,
    this.center,
  });

  static const kType = 'circularProgress';

  final double value;
  final double? size;
  final double? lineWidth;
  final Color? tint;
  final Color? trackColor;

  /// Node drawn inside the ring — typically a [LAText] or [LAImage].
  final LANode? center;

  @override
  String get type => kType;

  @override
  void writeProperties(Map<String, Object?> json) {
    json['value'] = value;
    json['size'] = size;
    json['lineWidth'] = lineWidth;
    json['tint'] = encodeColor(tint);
    json['track'] = encodeColor(trackColor);
    json['center'] = center?.toJson();
  }

  static LACircularProgress fromJson(Map<String, Object?> json) =>
      LACircularProgress(
        LANode._double(json['value']) ?? 0,
        size: LANode._double(json['size']),
        lineWidth: LANode._double(json['lineWidth']),
        tint: decodeColor(json['tint']),
        trackColor: decodeColor(json['track']),
        center: LANode._child(json['center']),
      );
}

// ===========================================================================
// metric
// ===========================================================================

/// A label/value pair — the workhorse of stat rows (`4.2 km`, `320 kcal`).
class LAMetric extends LANode {
  const LAMetric({
    required this.value,
    this.label,
    this.unit,
    this.symbol,
    this.align = LAAlign.start,
    this.tint,
    this.valueSize,
    this.labelSize,
  });

  static const kType = 'metric';

  final String value;
  final String? label;
  final String? unit;

  /// Optional SF Symbol shown next to the label.
  final String? symbol;
  final LAAlign align;
  final Color? tint;
  final double? valueSize;
  final double? labelSize;

  @override
  String get type => kType;

  @override
  void writeProperties(Map<String, Object?> json) {
    json['value'] = value;
    json['label'] = label;
    json['unit'] = unit;
    json['symbol'] = symbol;
    if (align != LAAlign.start) json['align'] = align.name;
    json['tint'] = encodeColor(tint);
    json['valueSize'] = valueSize;
    json['labelSize'] = labelSize;
  }

  static LAMetric fromJson(Map<String, Object?> json) => LAMetric(
        value: json['value']?.toString() ?? '',
        label: json['label']?.toString(),
        unit: json['unit']?.toString(),
        symbol: json['symbol']?.toString(),
        align: LAAlign.fromName(json['align']) ?? LAAlign.start,
        tint: decodeColor(json['tint']),
        valueSize: LANode._double(json['valueSize']),
        labelSize: LANode._double(json['labelSize']),
      );
}

// ===========================================================================
// countdown
// ===========================================================================

/// A self-updating timer.
///
/// This is the single most important component for battery life: SwiftUI's
/// `Text(date, style:)` ticks on its own, so a countdown needs **no** payload
/// updates at all. Prefer it over pushing a new string every second.
class LACountdown extends LANode {
  const LACountdown(
    this.until, {
    this.style = LACountdownStyle.timer,
    this.size,
    this.weight,
    this.color,
    this.align,
    this.monospacedDigit = true,
    this.prefix,
    this.suffix,
  });

  static const kType = 'countdown';

  /// Target instant. A past date counts up, a future date counts down.
  final DateTime until;
  final LACountdownStyle style;
  final double? size;
  final FontWeight? weight;
  final Color? color;
  final TextAlign? align;
  final bool monospacedDigit;
  final String? prefix;
  final String? suffix;

  @override
  String get type => kType;

  @override
  void writeProperties(Map<String, Object?> json) {
    // Seconds since epoch: Swift's `Date(timeIntervalSince1970:)` unit, and
    // three bytes shorter than milliseconds.
    json['until'] = until.toUtc().millisecondsSinceEpoch / 1000.0;
    if (style != LACountdownStyle.timer) json['style'] = style.name;
    json['size'] = size;
    json['weight'] = encodeFontWeight(weight);
    json['color'] = encodeColor(color);
    json['align'] = encodeTextAlign(align);
    if (!monospacedDigit) json['mono'] = false;
    json['prefix'] = prefix;
    json['suffix'] = suffix;
  }

  static LACountdown fromJson(Map<String, Object?> json) => LACountdown(
        DateTime.fromMillisecondsSinceEpoch(
          (((json['until'] as num?)?.toDouble() ?? 0) * 1000).round(),
          isUtc: true,
        ),
        style: LACountdownStyle.fromName(json['style']) ??
            LACountdownStyle.timer,
        size: LANode._double(json['size']),
        weight: decodeFontWeight(json['weight']),
        color: decodeColor(json['color']),
        align: decodeTextAlign(json['align']),
        monospacedDigit: json['mono'] != false,
        prefix: json['prefix']?.toString(),
        suffix: json['suffix']?.toString(),
      );
}

// ===========================================================================
// spacer / divider
// ===========================================================================

class LASpacer extends LANode {
  const LASpacer({this.minLength});

  static const kType = 'spacer';

  final double? minLength;

  @override
  String get type => kType;

  @override
  void writeProperties(Map<String, Object?> json) {
    json['minLength'] = minLength;
  }

  static LASpacer fromJson(Map<String, Object?> json) =>
      LASpacer(minLength: LANode._double(json['minLength']));
}

class LADivider extends LANode {
  const LADivider({this.color, this.thickness, this.vertical = false});

  static const kType = 'divider';

  final Color? color;
  final double? thickness;
  final bool vertical;

  @override
  String get type => kType;

  @override
  void writeProperties(Map<String, Object?> json) {
    json['color'] = encodeColor(color);
    json['thickness'] = thickness;
    if (vertical) json['vertical'] = true;
  }

  static LADivider fromJson(Map<String, Object?> json) => LADivider(
        color: decodeColor(json['color']),
        thickness: LANode._double(json['thickness']),
        vertical: json['vertical'] == true,
      );
}

// ===========================================================================
// padding / container
// ===========================================================================

class LAPadding extends LANode {
  const LAPadding({required this.insets, required this.child});

  static const kType = 'padding';

  final LAInsets insets;
  final LANode child;

  @override
  String get type => kType;

  @override
  void writeProperties(Map<String, Object?> json) {
    json['insets'] = insets.toJson();
    json['child'] = child.toJson();
  }

  static LAPadding fromJson(Map<String, Object?> json) => LAPadding(
        insets: LAInsets.fromJson(json['insets']) ?? const LAInsets(),
        child: LANode._child(json['child']) ?? const LASpacer(),
      );
}

class LAContainer extends LANode {
  const LAContainer({
    this.child,
    this.background,
    this.gradient,
    this.cornerRadius,
    this.borderColor,
    this.borderWidth,
    this.padding,
    this.width,
    this.height,
    this.align = LAAlign.center,
  });

  static const kType = 'container';

  final LANode? child;
  final Color? background;

  /// Two or more colors painted as a top-leading → bottom-trailing gradient.
  final List<Color>? gradient;
  final double? cornerRadius;
  final Color? borderColor;
  final double? borderWidth;
  final LAInsets? padding;
  final double? width;
  final double? height;
  final LAAlign align;

  @override
  String get type => kType;

  @override
  void writeProperties(Map<String, Object?> json) {
    json['child'] = child?.toJson();
    json['background'] = encodeColor(background);
    json['gradient'] = gradient?.map(encodeColor).toList();
    json['radius'] = cornerRadius;
    json['borderColor'] = encodeColor(borderColor);
    json['borderWidth'] = borderWidth;
    json['padding'] = padding?.toJson();
    json['width'] = width;
    json['height'] = height;
    if (align != LAAlign.center) json['align'] = align.name;
  }

  static LAContainer fromJson(Map<String, Object?> json) => LAContainer(
        child: LANode._child(json['child']),
        background: decodeColor(json['background']),
        gradient: (json['gradient'] as List?)
            ?.map(decodeColor)
            .whereType<Color>()
            .toList(),
        cornerRadius: LANode._double(json['radius']),
        borderColor: decodeColor(json['borderColor']),
        borderWidth: LANode._double(json['borderWidth']),
        padding: LAInsets.fromJson(json['padding']),
        width: LANode._double(json['width']),
        height: LANode._double(json['height']),
        align: LAAlign.fromName(json['align']) ?? LAAlign.center,
      );
}
