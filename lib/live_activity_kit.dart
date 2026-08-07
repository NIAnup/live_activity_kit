/// A universal, component-based framework for iOS Live Activities and the
/// Dynamic Island, driven entirely from Dart.
///
/// Apple does not let Flutter render inside a Live Activity — the UI must be
/// SwiftUI, in a widget extension. This package closes that gap by shipping a
/// declarative component tree from Dart as JSON and drawing it with a bundled
/// recursive SwiftUI renderer.
///
/// See the README for setup (`dart run live_activity_kit:setup`).
library;

export 'src/components/la.dart';
export 'src/components/node.dart'
    show
        LANode,
        LANodeDecodeException,
        LAText,
        LAImage,
        LARow,
        LAColumn,
        LAProgress,
        LACircularProgress,
        LAMetric,
        LACountdown,
        LASpacer,
        LADivider,
        LAPadding,
        LAContainer;
export 'src/components/style.dart'
    show LAAlign, LADistribution, LAImageSource, LACountdownStyle, LAInsets;
export 'src/bridge/live_activity_platform.dart'
    show LiveActivityPlatform, MethodChannelLiveActivity;
export 'src/live_activity.dart';
export 'src/models/activity.dart';
export 'src/models/layout.dart';
export 'src/store/live_activity_store.dart';
