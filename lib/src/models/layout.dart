import 'dart:ui' show Color;

import '../components/node.dart';
import '../components/style.dart';

/// The presentation regions iOS offers a Live Activity.
///
/// Each region gets its own component tree; the renderer draws whichever one
/// the system asks for. Any region you leave `null` falls back per the rules in
/// [LiveActivityLayout.resolve].
enum LARegion {
  /// Dynamic Island, collapsed, left of the sensor housing.
  compactLeading,

  /// Dynamic Island, collapsed, right of the sensor housing.
  compactTrailing,

  /// Dynamic Island when a second activity is competing for space. Room for
  /// roughly one glyph.
  minimal,

  /// Dynamic Island, expanded, left column.
  expandedLeading,

  /// Dynamic Island, expanded, right column.
  expandedTrailing,

  /// Dynamic Island, expanded, between the two columns under the housing.
  expandedCenter,

  /// Dynamic Island, expanded, full-width area beneath everything else.
  expandedBottom,

  /// Lock screen, notification-style banner, and the Home Screen / StandBy
  /// presentations on iOS 18+.
  lockScreen;

  static LARegion? fromName(Object? raw) {
    for (final v in LARegion.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// Colors applied around the rendered trees.
class LATheme {
  const LATheme({
    this.background,
    this.backgroundGradient,
    this.tint,
    this.foreground,
  });

  /// Lock-screen banner background. `null` keeps the system material.
  final Color? background;

  /// Two or more colors, painted top-leading → bottom-trailing.
  final List<Color>? backgroundGradient;

  /// `.keylineTint` for the Dynamic Island — the glow around the island when
  /// the activity updates.
  final Color? tint;

  /// Default text color for every node that does not set its own.
  final Color? foreground;

  bool get isEmpty =>
      background == null &&
      backgroundGradient == null &&
      tint == null &&
      foreground == null;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'background': encodeColor(background),
      'gradient': backgroundGradient?.map(encodeColor).toList(),
      'tint': encodeColor(tint),
      'foreground': encodeColor(foreground),
    };
    json.removeWhere((_, v) => v == null);
    return json;
  }

  static LATheme fromJson(Map<String, Object?> json) => LATheme(
        background: decodeColor(json['background']),
        backgroundGradient: (json['gradient'] as List?)
            ?.map(decodeColor)
            .whereType<Color>()
            .toList(),
        tint: decodeColor(json['tint']),
        foreground: decodeColor(json['foreground']),
      );
}

/// A complete Live Activity UI: one component tree per region.
class LiveActivityLayout {
  const LiveActivityLayout({
    this.lockScreen,
    this.compact,
    this.compactLeading,
    this.compactTrailing,
    this.minimal,
    this.expanded,
    this.expandedLeading,
    this.expandedTrailing,
    this.expandedCenter,
    this.expandedBottom,
    this.theme = const LATheme(),
    this.deepLink,
  });

  /// Lock screen / banner tree.
  final LANode? lockScreen;

  /// Shorthand: used for [LARegion.compactTrailing] when that is not set.
  final LANode? compact;
  final LANode? compactLeading;
  final LANode? compactTrailing;

  final LANode? minimal;

  /// Shorthand: used for [LARegion.expandedBottom] when no explicit expanded
  /// region is provided.
  final LANode? expanded;
  final LANode? expandedLeading;
  final LANode? expandedTrailing;
  final LANode? expandedCenter;
  final LANode? expandedBottom;

  final LATheme theme;

  /// URL opened when the user taps the activity. Handle it with your existing
  /// deep-link handling — the plugin forwards it through
  /// `LiveActivity.onDeepLink`.
  final String? deepLink;

  /// Resolves a region to the tree that should actually be drawn, applying the
  /// shorthand fallbacks:
  ///
  /// * `compactTrailing` ← `compact`
  /// * `expandedBottom`  ← `expanded` (only when no other expanded region is set)
  /// * `minimal`         ← `compactTrailing` ← `compact`
  /// * every region      ← `lockScreen` is **never** used as a fallback; the
  ///   lock-screen tree is almost always too tall for the island.
  LANode? resolve(LARegion region) => switch (region) {
        LARegion.lockScreen => lockScreen,
        LARegion.compactLeading => compactLeading,
        LARegion.compactTrailing => compactTrailing ?? compact,
        LARegion.minimal => minimal ?? compactTrailing ?? compact,
        LARegion.expandedLeading => expandedLeading,
        LARegion.expandedTrailing => expandedTrailing,
        LARegion.expandedCenter => expandedCenter,
        LARegion.expandedBottom => expandedBottom ?? _expandedFallback,
      };

  LANode? get _expandedFallback {
    final hasExplicit = expandedLeading != null ||
        expandedTrailing != null ||
        expandedCenter != null;
    return hasExplicit ? null : expanded;
  }

  bool get isEmpty =>
      LARegion.values.every((region) => resolve(region) == null);

  /// Only the regions that resolve to something are emitted, so an activity
  /// that only uses the lock screen ships one tree, not eight.
  Map<String, Object?> toJson() {
    final regions = <String, Object?>{};
    for (final region in LARegion.values) {
      final node = resolve(region);
      if (node != null) regions[region.name] = node.toJson();
    }
    final json = <String, Object?>{'regions': regions};
    if (!theme.isEmpty) json['theme'] = theme.toJson();
    if (deepLink != null) json['deepLink'] = deepLink;
    return json;
  }

  static LiveActivityLayout fromJson(Map<String, Object?> json) {
    final regions = (json['regions'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    LANode? node(LARegion region) {
      final raw = regions[region.name];
      return raw == null
          ? null
          : LANode.fromJson((raw as Map).cast<String, Object?>());
    }

    return LiveActivityLayout(
      lockScreen: node(LARegion.lockScreen),
      compactLeading: node(LARegion.compactLeading),
      compactTrailing: node(LARegion.compactTrailing),
      minimal: node(LARegion.minimal),
      expandedLeading: node(LARegion.expandedLeading),
      expandedTrailing: node(LARegion.expandedTrailing),
      expandedCenter: node(LARegion.expandedCenter),
      expandedBottom: node(LARegion.expandedBottom),
      theme: LATheme.fromJson(
        (json['theme'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      deepLink: json['deepLink']?.toString(),
    );
  }

  /// Returns a copy with the given regions replaced. Used by
  /// `LiveActivity.update` so a partial update keeps the untouched regions.
  LiveActivityLayout copyWith({
    LANode? lockScreen,
    LANode? compact,
    LANode? compactLeading,
    LANode? compactTrailing,
    LANode? minimal,
    LANode? expanded,
    LANode? expandedLeading,
    LANode? expandedTrailing,
    LANode? expandedCenter,
    LANode? expandedBottom,
    LATheme? theme,
    String? deepLink,
  }) =>
      LiveActivityLayout(
        lockScreen: lockScreen ?? this.lockScreen,
        compact: compact ?? this.compact,
        compactLeading: compactLeading ?? this.compactLeading,
        compactTrailing: compactTrailing ?? this.compactTrailing,
        minimal: minimal ?? this.minimal,
        expanded: expanded ?? this.expanded,
        expandedLeading: expandedLeading ?? this.expandedLeading,
        expandedTrailing: expandedTrailing ?? this.expandedTrailing,
        expandedCenter: expandedCenter ?? this.expandedCenter,
        expandedBottom: expandedBottom ?? this.expandedBottom,
        theme: theme ?? this.theme,
        deepLink: deepLink ?? this.deepLink,
      );
}
