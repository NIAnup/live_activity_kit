import Flutter
import UIKit

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Flutter entry point.
///
/// Everything the plugin does is gated on iOS 16.1: on older systems every call
/// fails with `unsupported` rather than crashing, so a Flutter app can ship one
/// binary and branch on `LiveActivity.support()`.
public class LiveActivityKitPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?
    private var pendingEvents: [[String: Any]] = []
    private var storeObserver: Any?

    // MARK: - Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = LiveActivityKitPlugin()

        let channel = FlutterMethodChannel(
            name: "live_activity_kit",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)

        let events = FlutterEventChannel(
            name: "live_activity_kit/events",
            binaryMessenger: registrar.messenger()
        )
        events.setStreamHandler(instance)

        instance.start()
    }

    private func start() {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            let manager = LiveActivityManager.shared
            manager.onEvent = { [weak self] event in self?.send(event) }
            // Reattach to activities that outlived the previous app launch.
            manager.restore()
        }
        #endif

        storeObserver = LiveActivityAppGroup.observeChanges { [weak self] key in
            self?.send(["type": "store", "key": key ?? ""])
        }
    }

    // MARK: - Method channel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return unsupported(result) }

        let manager = LiveActivityManager.shared
        let arguments = call.arguments as? [String: Any] ?? [:]

        do {
            switch call.method {
            case "checkSupport":
                result(manager.support())

            case "show":
                // Images must be in the shared container before the first frame
                // is drawn, otherwise the activity opens with holes in it.
                prefetching(arguments) {
                    do {
                        result(try manager.request(arguments))
                    } catch {
                        self.fail(error, result)
                    }
                }

            case "update":
                prefetching(arguments) {
                    do {
                        try manager.update(arguments)
                        result(nil)
                    } catch {
                        self.fail(error, result)
                    }
                }

            case "end":
                try manager.end(arguments)
                result(nil)

            case "endAll":
                manager.endAll(immediate: arguments["immediate"] as? Bool ?? false)
                result(nil)

            case "activities":
                result(manager.all())

            case "activity":
                guard let id = arguments["id"] as? String else {
                    return result(invalidArgument("Missing id."))
                }
                let all = manager.all()
                result(all.first { ($0["id"] as? String) == id })

            case "pushToStartToken":
                result(manager.pushToStartToken())

            case "storeWrite":
                guard let key = arguments["key"] as? String,
                      let value = arguments["value"] as? String else {
                    return result(invalidArgument("storeWrite needs key and value."))
                }
                try LiveActivityAppGroup.write(value, forKey: key)
                result(nil)

            case "storeRead":
                guard let key = arguments["key"] as? String else {
                    return result(invalidArgument("storeRead needs a key."))
                }
                result(LiveActivityAppGroup.read(forKey: key))

            default:
                result(FlutterMethodNotImplemented)
            }
        } catch {
            fail(error, result)
        }
        #else
        unsupported(result)
        #endif
    }

    private func prefetching(_ arguments: [String: Any], then work: @escaping () -> Void) {
        guard let payload = arguments["layout"] as? String else { return work() }
        LiveActivityImagePrefetcher.prefetch(payload: payload, completion: work)
    }

    // MARK: - Deep links

    /// Live Activity taps arrive as a universal-link-style open. Forward them to
    /// Dart instead of requiring every app to reimplement the plumbing.
    public func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]) -> Void
    ) -> Bool {
        guard let url = userActivity.webpageURL else { return false }
        send(["type": "deepLink", "url": url.absoluteString])
        return false  // Never claim the link: other plugins may want it too.
    }

    public func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        send(["type": "deepLink", "url": url.absoluteString])
        return false
    }

    // MARK: - Event channel

    public func onListen(
        withArguments arguments: Any?,
        eventSink: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = eventSink
        // Events emitted before Dart subscribed (push tokens in particular
        // arrive within milliseconds of `show`) would otherwise be lost.
        pendingEvents.forEach { eventSink($0) }
        pendingEvents.removeAll()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    private func send(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let sink = self.eventSink {
                sink(event)
            } else {
                // Bounded: a runaway producer must not grow memory without end.
                if self.pendingEvents.count >= 32 { self.pendingEvents.removeFirst() }
                self.pendingEvents.append(event)
            }
        }
    }

    // MARK: - Errors

    private func fail(_ error: Error, _ result: FlutterResult) {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *), let failure = error as? LiveActivityManager.Failure {
            return result(FlutterError(
                code: failure.code,
                message: failure.message,
                details: nil
            ))
        }
        #endif
        if let failure = error as? LiveActivityAppGroup.Failure {
            return result(FlutterError(
                code: "app_group_missing",
                message: failure.errorDescription,
                details: nil
            ))
        }
        result(FlutterError(
            code: "unknown",
            message: error.localizedDescription,
            details: nil
        ))
    }

    private func unsupported(_ result: FlutterResult) {
        result(FlutterError(
            code: "unsupported",
            message: "Live Activities require iOS 16.1 or later.",
            details: nil
        ))
    }

    private func invalidArgument(_ message: String) -> FlutterError {
        FlutterError(code: "invalid_argument", message: message, details: nil)
    }
}
