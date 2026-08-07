import Foundation
import Flutter

/// Copies every image a payload references into the shared App Group container
/// before the activity is started or updated.
///
/// The widget extension cannot read the app's bundle and must not perform
/// network I/O while rendering, so this is where asset bytes and remote artwork
/// actually cross the process boundary. Anything that fails to arrive in time
/// simply renders as empty space and lands on a later update — a Live Activity
/// is never blocked on a download.
enum LiveActivityImagePrefetcher {

    /// How long `show`/`update` will wait for downloads before going ahead
    /// anyway. Live Activities are time-sensitive; a stalled CDN must not
    /// delay the UI the user asked for.
    static let timeout: TimeInterval = 3

    static func prefetch(payload: String, completion: @escaping () -> Void) {
        let references = images(in: payload)
        guard !references.isEmpty else { return completion() }

        let group = DispatchGroup()
        for reference in references {
            let relativePath = "images/\(LAImageLoader.cacheKey(for: reference.value)).img"
            if LiveActivityAppGroup.fileURL(relativePath: relativePath) != nil {
                continue  // Already cached — images are content-addressed by value.
            }
            group.enter()
            fetch(reference) { data in
                if let data {
                    try? LiveActivityAppGroup.writeFile(data, relativePath: relativePath)
                }
                group.leave()
            }
        }

        // Whichever comes first wins. Both callbacks land on the main queue, so
        // the flag needs no further synchronisation.
        var didFinish = false
        let finish = {
            guard !didFinish else { return }
            didFinish = true
            completion()
        }
        group.notify(queue: .main, execute: finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: finish)
    }

    // MARK: - Private

    private struct Reference {
        let source: String
        let value: String
    }

    private static func fetch(_ reference: Reference, completion: @escaping (Data?) -> Void) {
        switch reference.source {
        case "asset":
            completion(assetData(reference.value))
        case "network":
            guard let url = URL(string: reference.value) else { return completion(nil) }
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            URLSession.shared.dataTask(with: request) { data, response, _ in
                let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
                completion(ok ? data : nil)
            }.resume()
        default:
            completion(nil)
        }
    }

    private static func assetData(_ assetKey: String) -> Data? {
        let key = FlutterDartProject.lookupKey(forAsset: assetKey)
        guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
            return nil
        }
        return FileManager.default.contents(atPath: path)
    }

    /// Walks the decoded tree for `image` nodes that need bytes.
    private static func images(in payload: String) -> [Reference] {
        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return [] }

        var found: [Reference] = []
        var seen = Set<String>()

        func walk(_ value: Any) {
            if let list = value as? [Any] {
                list.forEach(walk)
                return
            }
            guard let node = value as? [String: Any] else { return }
            if node["type"] as? String == "image",
               let source = node["source"] as? String,
               source == "asset" || source == "network",
               let assetValue = node["value"] as? String,
               seen.insert(assetValue).inserted {
                found.append(Reference(source: source, value: assetValue))
            }
            for child in node.values { walk(child) }
        }

        walk(root)
        return found
    }
}
