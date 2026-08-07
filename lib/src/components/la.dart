import 'dart:ui' show Color, FontWeight, TextAlign;

import 'node.dart';
import 'style.dart';

/// The component DSL.
///
/// `LA` is a namespace of const factories, not a widget hierarchy. Every call
/// returns an immutable [LANode] that serializes to JSON and is drawn by the
/// bundled SwiftUI renderer inside the widget extension.
///
/// ```dart
/// LA.column([
///   LA.text('Next meal', weight: FontWeight.bold),
///   LA.text('Lunch — 1:00 PM'),
///   LA.progress(0.65),
/// ])
/// ```
abstract final class LA {
  /// A run of text. Emoji and any Unicode SwiftUI can draw are supported.
  static LAText text(
    String value, {
    double? size,
    FontWeight? weight,
    Color? color,
    TextAlign? align,
    int? maxLines,
    double? opacity,
    bool italic = false,
    bool monospacedDigit = false,
    bool uppercase = false,
  }) =>
      LAText(
        value,
        size: size,
        weight: weight,
        color: color,
        align: align,
        maxLines: maxLines,
        opacity: opacity,
        italic: italic,
        monospacedDigit: monospacedDigit,
        uppercase: uppercase,
      );

  /// An SF Symbol, bundled asset, cached network image, or App Group file.
  ///
  /// Prefer [symbol] where you can: SF Symbols cost zero bytes of payload and
  /// never miss a frame waiting on I/O.
  static LAImage image({
    required LAImageSource source,
    required String value,
    double? size,
    double? width,
    double? height,
    Color? color,
    double? cornerRadius,
  }) =>
      LAImage(
        source: source,
        value: value,
        size: size,
        width: width,
        height: height,
        color: color,
        cornerRadius: cornerRadius,
      );

  /// An SF Symbol, e.g. `LA.symbol('figure.run')`.
  static LAImage symbol(String name, {double? size, Color? color}) =>
      LAImage.symbol(name, size: size, color: color);

  /// A Flutter asset. Run `dart run live_activity_kit:setup --sync-assets`
  /// (or call [LiveActivityAssets.sync]) so the extension can read it.
  static LAImage asset(
    String assetKey, {
    double? width,
    double? height,
    double? cornerRadius,
  }) =>
      LAImage.asset(
        assetKey,
        width: width,
        height: height,
        cornerRadius: cornerRadius,
      );

  /// A remote image. Downloaded once and cached in the App Group container.
  static LAImage networkImage(
    String url, {
    double? width,
    double? height,
    double? cornerRadius,
  }) =>
      LAImage.network(
        url,
        width: width,
        height: height,
        cornerRadius: cornerRadius,
      );

  /// Horizontal stack (SwiftUI `HStack`).
  static LARow row(
    List<LANode> children, {
    double? spacing,
    LAAlign align = LAAlign.center,
    LADistribution distribution = LADistribution.start,
  }) =>
      LARow(children, spacing: spacing, align: align, distribution: distribution);

  /// Vertical stack (SwiftUI `VStack`).
  static LAColumn column(
    List<LANode> children, {
    double? spacing,
    LAAlign align = LAAlign.start,
    LADistribution distribution = LADistribution.start,
  }) =>
      LAColumn(children,
          spacing: spacing, align: align, distribution: distribution);

  /// A linear progress bar. [value] is 0.0 – 1.0.
  static LAProgress progress(
    double value, {
    Color? tint,
    Color? trackColor,
    double? height,
    double? cornerRadius,
    String? label,
  }) =>
      LAProgress(
        value,
        tint: tint,
        trackColor: trackColor,
        height: height,
        cornerRadius: cornerRadius,
        label: label,
      );

  /// A progress ring, optionally with a node in the middle.
  static LACircularProgress circularProgress(
    double value, {
    double? size,
    double? lineWidth,
    Color? tint,
    Color? trackColor,
    LANode? center,
  }) =>
      LACircularProgress(
        value,
        size: size,
        lineWidth: lineWidth,
        tint: tint,
        trackColor: trackColor,
        center: center,
      );

  /// A value with an optional label, unit and icon — for stat rows.
  static LAMetric metric(
    String value, {
    String? label,
    String? unit,
    String? symbol,
    LAAlign align = LAAlign.start,
    Color? tint,
    double? valueSize,
    double? labelSize,
  }) =>
      LAMetric(
        value: value,
        label: label,
        unit: unit,
        symbol: symbol,
        align: align,
        tint: tint,
        valueSize: valueSize,
        labelSize: labelSize,
      );

  /// A timer that ticks on its own, with no payload updates.
  ///
  /// Use this instead of pushing a new [text] every second — see the
  /// "Frequent updates" section of the README.
  static LACountdown countdown(
    DateTime until, {
    LACountdownStyle style = LACountdownStyle.timer,
    double? size,
    FontWeight? weight,
    Color? color,
    TextAlign? align,
    bool monospacedDigit = true,
    String? prefix,
    String? suffix,
  }) =>
      LACountdown(
        until,
        style: style,
        size: size,
        weight: weight,
        color: color,
        align: align,
        monospacedDigit: monospacedDigit,
        prefix: prefix,
        suffix: suffix,
      );

  /// A stopwatch counting up from [since].
  static LACountdown stopwatch(
    DateTime since, {
    double? size,
    FontWeight? weight,
    Color? color,
  }) =>
      LACountdown(
        since,
        style: LACountdownStyle.timer,
        size: size,
        weight: weight,
        color: color,
      );

  /// Flexible empty space inside a [row] or [column].
  static LASpacer spacer({double? minLength}) =>
      LASpacer(minLength: minLength);

  /// A hairline rule.
  static LADivider divider({
    Color? color,
    double? thickness,
    bool vertical = false,
  }) =>
      LADivider(color: color, thickness: thickness, vertical: vertical);

  /// Insets around [child]. Provide [all], or the symmetric/edge values.
  static LAPadding padding(
    LANode child, {
    double? all,
    double? horizontal,
    double? vertical,
    double? top,
    double? left,
    double? bottom,
    double? right,
  }) =>
      LAPadding(
        insets: LAInsets(
          top: top ?? vertical ?? all ?? 0,
          left: left ?? horizontal ?? all ?? 0,
          bottom: bottom ?? vertical ?? all ?? 0,
          right: right ?? horizontal ?? all ?? 0,
        ),
        child: child,
      );

  /// A decorated box: background or gradient, corner radius, border, size.
  static LAContainer container({
    LANode? child,
    Color? background,
    List<Color>? gradient,
    double? cornerRadius,
    Color? borderColor,
    double? borderWidth,
    LAInsets? padding,
    double? width,
    double? height,
    LAAlign align = LAAlign.center,
  }) =>
      LAContainer(
        child: child,
        background: background,
        gradient: gradient,
        cornerRadius: cornerRadius,
        borderColor: borderColor,
        borderWidth: borderWidth,
        padding: padding,
        width: width,
        height: height,
        align: align,
      );
}
