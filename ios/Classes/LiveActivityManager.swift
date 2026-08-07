import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Owns every `Activity` this app has started, and translates the Dart-side
/// request maps into ActivityKit calls.
///
/// Availability is fiddly here on purpose: the package supports iOS 16.1, but
/// the ergonomic `ActivityContent` API (stale dates, relevance scores) only
/// arrived in 16.2, and push-to-start in 17.2. Each capability is gated where
/// it is used rather than raising the deployment target.
@available(iOS 16.1, *)
final class LiveActivityManager {

    enum Failure: Error {
        case unsupported
        case disabled
        case notFound(String)
        case tooManyActivities
        case invalidArgument(String)

        var code: String {
            switch self {
            case .unsupported: return "unsupported"
            case .disabled: return "disabled"
            case .notFound: return "not_found"
            case .tooManyActivities: return "too_many_activities"
            case .invalidArgument: return "invalid_argument"
            }
        }

        var message: String {
            switch self {
            case .unsupported:
                return "Live Activities require iOS 16.1 or later and NSSupportsLiveActivities in Info.plist."
            case .disabled:
                return "The user has turned Live Activities off for this app in Settings."
            case .notFound(let id):
                return "No running Live Activity with id \"\(id)\"."
            case .tooManyActivities:
                return "iOS refused the request — too many concurrent Live Activities."
            case .invalidArgument(let detail):
                return detail
            }
        }
    }

    /// Events pushed to Dart over the `EventChannel`.
    var onEvent: (([String: Any]) -> Void)?

    static let shared = LiveActivityManager()

    private var activities: [String: Activity<LiveActivityKitAttributes>] = [:]
    private var observers: [String: [Task<Void, Never>]] = [:]
    private var revisions: [String: Int] = [:]
    private var pushToStartTask: Task<Void, Never>?

    private init() {}

    // MARK: - Capability

    func support() -> [String: Any] {
        let info = ActivityAuthorizationInfo()
        return [
            "isSupported": true,
            "areActivitiesEnabled": info.areActivitiesEnabled,
            "supportsDynamicIsland": Self.hasDynamicIsland,
            "systemVersion": UIDeviceSystemVersion,
        ]
    }

    /// The Dynamic Island is not exposed as a capability flag, so this reads
    /// the device model and checks against the identifiers that have one.
    private static var hasDynamicIsland: Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        // Simulators report their host identifier; fall back to the model the
        // simulator is impersonating.
        let model: String
        if identifier == "i386" || identifier == "x86_64" || identifier == "arm64" {
            model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? identifier
        } else {
            model = identifier
        }
        guard model.hasPrefix("iPhone") else { return false }
        let components = model.dropFirst("iPhone".count).split(separator: ",")
        guard let major = components.first.flatMap({ Int($0) }),
              let minor = components.dropFirst().first.flatMap({ Int($0) })
        else { return false }
        // iPhone15,2 = 14 Pro — the first with a Dynamic Island. Everything from
        // iPhone16,x onwards has one.
        if major > 15 { return true }
        if major == 15 { return minor >= 2 }
        return false
    }

    private var UIDeviceSystemVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    // MARK: - Lifecycle

    /// Reattaches to activities that survived an app relaunch. Called once from
    /// the plugin's `register`.
    func restore() {
        for activity in Activity<LiveActivityKitAttributes>.activities {
            activities[activity.attributes.id] = activity
            observe(activity)
        }
    }

    @discardableResult
    func request(_ request: [String: Any]) throws -> [String: Any] {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw Failure.disabled
        }
        guard let id = request["id"] as? String, !id.isEmpty else {
            throw Failure.invalidArgument("Missing activity id.")
        }
        guard let payload = request["layout"] as? String else {
            throw Failure.invalidArgument("Missing layout.")
        }

        // Starting an activity that is already running would leave an orphan on
        // the Lock Screen, so treat it as an update instead.
        if activities[id] != nil {
            try update(request)
            return describe(id: id)
        }

        let attributes = LiveActivityKitAttributes(id: id)
        let revision = nextRevision(for: id)
        let state = LiveActivityKitAttributes.ContentState(payload: payload, revision: revision)
        let pushType: PushType? = (request["enablePush"] as? Bool == true) ? .token : nil

        let activity: Activity<LiveActivityKitAttributes>
        do {
            if #available(iOS 16.2, *) {
                activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(
                        state: state,
                        staleDate: Self.date(request["staleAt"]),
                        relevanceScore: (request["relevance"] as? Double) ?? 0
                    ),
                    pushType: pushType
                )
            } else {
                activity = try Activity.request(
                    attributes: attributes,
                    contentState: state,
                    pushType: pushType
                )
            }
        } catch {
            throw Self.mapped(error)
        }

        activities[id] = activity
        observe(activity)
        return describe(id: id)
    }

    func update(_ request: [String: Any]) throws {
        guard let id = request["id"] as? String else {
            throw Failure.invalidArgument("Missing activity id.")
        }
        guard let activity = activities[id] else { throw Failure.notFound(id) }
        guard let payload = request["layout"] as? String else {
            throw Failure.invalidArgument("Missing layout.")
        }

        let state = LiveActivityKitAttributes.ContentState(
            payload: payload,
            revision: nextRevision(for: id)
        )
        let alert = Self.alert(request["alert"])

        Task {
            if #available(iOS 16.2, *) {
                await activity.update(
                    ActivityContent(
                        state: state,
                        staleDate: Self.date(request["staleAt"]),
                        relevanceScore: (request["relevance"] as? Double) ?? 0
                    ),
                    alertConfiguration: alert
                )
            } else {
                await activity.update(using: state, alertConfiguration: alert)
            }
        }
    }

    func end(_ request: [String: Any]) throws {
        guard let id = request["id"] as? String else {
            throw Failure.invalidArgument("Missing activity id.")
        }
        guard let activity = activities[id] else { throw Failure.notFound(id) }

        let policy = Self.dismissalPolicy(request["policy"])
        let finalState = (request["layout"] as? String).map {
            LiveActivityKitAttributes.ContentState(
                payload: $0,
                revision: nextRevision(for: id)
            )
        }

        activities.removeValue(forKey: id)

        Task { [weak self] in
            if #available(iOS 16.2, *) {
                let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
                await activity.end(content, dismissalPolicy: policy)
            } else {
                await activity.end(using: finalState, dismissalPolicy: policy)
            }
            guard let self else { return }
            await MainActor.run { self.cancelObservers(for: id) }
        }
    }

    func endAll(immediate: Bool) {
        let policy: ActivityUIDismissalPolicy = immediate ? .immediate : .default
        let running = activities
        activities.removeAll()
        Task { [weak self] in
            for (id, activity) in running {
                if #available(iOS 16.2, *) {
                    await activity.end(nil, dismissalPolicy: policy)
                } else {
                    await activity.end(using: nil, dismissalPolicy: policy)
                }
                guard let self else { return }
                await MainActor.run { self.cancelObservers(for: id) }
            }
        }
    }

    // MARK: - Queries

    func all() -> [[String: Any]] {
        activities.keys.map { describe(id: $0) }
    }

    func describe(id: String) -> [String: Any] {
        guard let activity = activities[id] else {
            return ["id": id, "activityId": "", "state": "dismissed"]
        }
        var result: [String: Any] = [
            "id": id,
            "activityId": activity.id,
            "state": Self.name(for: activity.activityState),
        ]
        if let token = activity.pushToken {
            result["pushToken"] = Self.hex(token)
        }
        return result
    }

    /// iOS 17.2+ push-to-start token. Starts the observation task on first ask.
    func pushToStartToken() -> String? {
        guard #available(iOS 17.2, *) else { return nil }
        observePushToStart()
        return Activity<LiveActivityKitAttributes>.pushToStartToken.map(Self.hex)
    }

    // MARK: - Observation

    private func observe(_ activity: Activity<LiveActivityKitAttributes>) {
        let id = activity.attributes.id
        cancelObservers(for: id)

        let stateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                self?.emit([
                    "type": "state",
                    "id": id,
                    "state": Self.name(for: state),
                ])
                if state == .dismissed || state == .ended, let self {
                    await MainActor.run {
                        _ = self.activities.removeValue(forKey: id)
                    }
                }
            }
        }

        let tokenTask = Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                self?.emit([
                    "type": "pushToken",
                    "id": id,
                    "token": Self.hex(token),
                ])
            }
        }

        observers[id] = [stateTask, tokenTask]
    }

    private func observePushToStart() {
        guard #available(iOS 17.2, *), pushToStartTask == nil else { return }
        pushToStartTask = Task { [weak self] in
            for await token in Activity<LiveActivityKitAttributes>.pushToStartTokenUpdates {
                self?.emit([
                    "type": "pushToStartToken",
                    "token": Self.hex(token),
                ])
            }
        }
    }

    private func cancelObservers(for id: String) {
        observers[id]?.forEach { $0.cancel() }
        observers[id] = nil
    }

    private func emit(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    // MARK: - Helpers

    /// ActivityKit ignores an update whose content state equals the current
    /// one. Re-rendering an unchanged tree is legitimate (a theme change, a
    /// forced refresh), so every push carries a fresh revision.
    private func nextRevision(for id: String) -> Int {
        let next = (revisions[id] ?? 0) + 1
        revisions[id] = next
        return next
    }

    private static func date(_ raw: Any?) -> Date? {
        guard let seconds = raw as? Double else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func alert(_ raw: Any?) -> AlertConfiguration? {
        guard let json = raw as? [String: Any],
              let title = json["title"] as? String,
              let body = json["body"] as? String else { return nil }
        if let sound = json["sound"] as? String {
            return AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: title),
                body: LocalizedStringResource(stringLiteral: body),
                sound: .named(sound)
            )
        }
        return AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: title),
            body: LocalizedStringResource(stringLiteral: body),
            sound: .default
        )
    }

    private static func dismissalPolicy(_ raw: Any?) -> ActivityUIDismissalPolicy {
        guard let json = raw as? [String: Any] else { return .default }
        switch json["dismissal"] as? String {
        case "immediate":
            return .immediate
        case "after":
            guard let date = date(json["dismissAt"]) else { return .default }
            return .after(date)
        default:
            return .default
        }
    }

    private static func name(for state: ActivityState) -> String {
        switch state {
        case .active: return "active"
        case .ended: return "ended"
        case .dismissed: return "dismissed"
        default:
            if #available(iOS 17.0, *), state == .stale { return "stale" }
            return "unknown"
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func mapped(_ error: Error) -> Failure {
        let description = String(describing: error)
        if description.contains("unsupported") || description.contains("denied") {
            return .disabled
        }
        if description.contains("tooManyActivities")
            || description.contains("targetMaximumExceeded") {
            return .tooManyActivities
        }
        return .invalidArgument(error.localizedDescription)
    }
}

#endif
