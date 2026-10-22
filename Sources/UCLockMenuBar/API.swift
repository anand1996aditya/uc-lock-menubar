import Foundation

enum APIError: LocalizedError {
    case sessionExpired
    case badResponse(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .sessionExpired: return "Session expired. Update the token in Settings."
        case .badResponse(let message): return message
        case .transport(let message): return message
        }
    }
}

struct APIClient {
    let config: Config

    func fetch(_ body: [String: Any], path: String = "/supply/appliances/getScreenDetails",
               timeout: TimeInterval = 25) async throws -> [String: Any] {
        guard let url = URL(string: "https://www.urbanclap.com/api/v2" + path) else { throw APIError.badResponse("Bad API URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        for (key, value) in RequestBodies.headers(config) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badResponse("No HTTP response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw APIError.sessionExpired
        }
        guard http.statusCode == 200 else {
            throw APIError.badResponse("HTTP \(http.statusCode)")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badResponse("Response was not JSON")
        }
        if let isError = object["isError"] as? Bool, isError {
            let message = ((object["success"] as? [String: Any])?["message"] as? String) ?? "API returned an error"
            throw APIError.badResponse(message)
        }
        return object
    }
}

struct DeviceInfo {
    var name: String = "Smart lock"
    var battery: Int?
    var batteryCritical: Bool = false
    var artworkURL: URL?
}

struct Activity: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let group: String
    let imageURL: URL?
    let occurredAt: Date?
    let lockActivityId: String?
    func withImageURL(_ url: URL?) -> Activity {
        Activity(id: id, title: title, subtitle: subtitle, group: group, imageURL: url,
                 occurredAt: occurredAt, lockActivityId: lockActivityId)
    }
    var isDoorbell: Bool { title.lowercased().contains("door") }
    var isUnlock: Bool { title.lowercased().contains("unlocked") }
    var isRecent: Bool {
        guard let occurredAt else { return false }
        return Date().timeIntervalSince(occurredAt) < 15 * 60
    }
    var timeText: String {
        subtitle.components(separatedBy: "•").first?.trimmingCharacters(in: .whitespaces) ?? subtitle
    }
    var detailText: String {
        let parts = subtitle.components(separatedBy: "•")
        return parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
    }
}

extension APIClient {
    func fetchWidgetAlert(timeout: TimeInterval = 25) async throws -> [String: Any] {
        try await fetch(RequestBodies.widgetAlert(config),
                       path: "/marketplace/booking/getHomescreenRequestStateWidget",
                       timeout: timeout)
    }

    func fetchRemoteUnlockPage(lockActivityId: String, timeout: TimeInterval = 25) async throws -> [String: Any] {
        try await fetch(RequestBodies.remoteUnlockPage(config, lockActivityId: lockActivityId),
                       path: "/supply/appliances/getScreenDetails",
                       timeout: timeout)
    }
}

enum Parser {
    static func device(from object: [String: Any]) -> DeviceInfo {
        var info = DeviceInfo()
        guard let dataStore = dataStore(from: object) else { return info }

        if let card = dataStore["applianceDetailsCard"] as? [String: Any] {
            if let textStack = card["textStack"] as? [String: Any],
               let items = textStack["items"] as? [[String: Any]] {
                for item in items {
                    guard let data = item["data"] as? [String: Any] else { continue }
                    if let text = data["text"] as? String {
                        info.name = text.replacingOccurrences(of: "\n", with: " ")
                    }
                    if let tags = data["tags"] as? [[String: Any]],
                       let first = tags.first,
                       let tagText = first["text"] as? String,
                       let value = batteryValue(in: tagText) {
                        info.battery = value
                    }
                }
            }
            if let headerMedia = card["headerMedia"] as? [String: Any],
               let media = headerMedia["media"] as? [String: Any],
               let props = media["props"] as? [String: Any],
               let remote = props["remoteSrc"] as? [String: Any],
               let base = remote["base_url"] as? String,
               let path = remote["s3_path"] as? String {
                let suffix = (remote["high_res"] as? String) ?? ""
                info.artworkURL = URL(string: base + path + suffix)
            }
        }
        if let nudge = dataStore["low_battery_nudge"] as? [String: Any],
           (nudge["widgetState"] as? String) == "visible" {
            info.batteryCritical = true
        }
        return info
    }

    static func activities(from object: [String: Any]) -> [Activity] {
        guard let dataStore = dataStore(from: object) else { return [] }
        var orderedIDs: [String] = []
        if let data = object["success"] as? [String: Any],
           let inner = data["data"] as? [String: Any],
           let layout = inner["layout"] as? [String: Any],
           let widgets = layout["widgets"] as? [String: Any],
           let defaults = widgets["default"] as? [[String: Any]] {
            orderedIDs = defaults.compactMap { $0["id"] as? String }
        }
        if orderedIDs.isEmpty { orderedIDs = Array(dataStore.keys).sorted() }

        var result: [Activity] = []
        var group = "Today"
        for id in orderedIDs {
            if id.hasPrefix("timeStampHeading"), let store = dataStore[id] as? [String: Any] {
                group = headingText(in: store) ?? group
                continue
            }
            guard id.hasPrefix("activity_"), !id.contains("divider"),
                  let store = dataStore[id] as? [String: Any] else { continue }
            if let activity = activity(id: id, store: store, group: group) {
                result.append(activity)
            }
        }
        return result
    }

    static func widgetAlerts(fromWidget object: [String: Any]) -> [(lockActivityId: String, timeText: String, message: String)] {
        guard let store = dataStore(from: object),
              let widget = store["homescreen_bottom_widget"] as? [String: Any],
              let groups = widget["items"] as? [[Any]] else { return [] }
        var alerts: [(String, String, String)] = []
        for group in groups {
            for item in group {
                guard let dict = item as? [String: Any],
                      let props = dict["props"] as? [String: Any],
                      let right = props["rightItem"] as? [String: Any],
                      let rightProps = right["props"] as? [String: Any],
                      let ctas = rightProps["ctas"] as? [[String: Any]],
                      let cta = ctas.first,
                      let press = cta["onButtonPress"] as? [String: Any],
                      let data = press["data"] as? [String: Any],
                      let params = data["params"] as? [String: Any],
                      let lockActivityId = params["lockActivityId"] as? String else { continue }
                let event = press["event"] as? [String: Any]
                let kind = event?["event_value_2"] as? String ?? ""
                guard kind == "REMOTE_UNLOCK" else { continue }
                var message = "Someone is at your doorstep"
                var timeText = ""
                if let stack = props["textStack"] as? [String: Any],
                   let items = stack["items"] as? [[String: Any]] {
                    let texts = items.compactMap { ($0["data"] as? [String: Any])?["text"] as? String }
                    if let first = texts.first, !first.isEmpty { message = first }
                    if texts.count > 1 { timeText = texts[1] }
                }
                alerts.append((lockActivityId, timeText, message))
            }
        }
        return alerts
    }

    static func remoteUnlockAlertId(fromWidget object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8),
              text.contains("REMOTE_UNLOCK") else { return nil }
        let pattern = #""lockActivityId"\s*:\s*"([a-f0-9]{24})""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func unlockPagePhotoURL(fromPage object: [String: Any]) -> URL? {
        var found: URL?
        func walk(_ value: Any) {
            if found != nil { return }
            if let dict = value as? [String: Any] {
                if let remote = dict["remoteSrcExternal"] as? [String: Any],
                   let raw = remote["url"] as? String,
                   raw.contains("content.urbancompany.com/p/"),
                   let url = URL(string: raw) {
                    found = url
                    return
                }
                for (_, child) in dict { walk(child) }
            } else if let array = value as? [Any] {
                for child in array { walk(child) }
            }
        }
        walk(object)
        return found
    }

    static func dataStore(from object: [String: Any]) -> [String: Any]? {
        guard let success = object["success"] as? [String: Any],
              let data = success["data"] as? [String: Any],
              let store = data["dataStore"] as? [String: Any] else { return nil }
        return store
    }

    private static func headingText(in store: [String: Any]) -> String? {
        guard let items = store["items"] as? [[String: Any]],
              let data = items.first?["data"] as? [String: Any],
              let stack = data["adsTextStack"] as? [String: Any],
              let stackItems = stack["items"] as? [[String: Any]],
              let first = stackItems.first,
              let data2 = first["data"] as? [String: Any] else { return nil }
        return data2["text"] as? String
    }

    private static func activity(id: String, store: [String: Any], group: String) -> Activity? {
        guard let items = store["items"] as? [[String: Any]] else { return nil }
        var descriptions: [String] = []
        var imageURL: URL?
        for item in items {
            guard let data = item["data"] as? [String: Any] else { continue }
            if let stack = data["adsTextStack"] as? [String: Any],
               let stackItems = stack["items"] as? [[String: Any]] {
                for entry in stackItems where (entry["type"] as? String) == "description" {
                    if let d = entry["data"] as? [String: Any], let text = d["text"] as? String {
                        descriptions.append(text)
                    }
                }
            }
            if let mediaContent = data["mediaContent"] as? [String: Any],
               let props = mediaContent["props"] as? [String: Any],
               let image = props["image"] as? [String: Any],
               let remote = image["remoteSrcExternal"] as? [String: Any],
               let urlString = remote["url"] as? String {
                imageURL = URL(string: urlString)
            }
        }
        guard let title = descriptions.first else { return nil }
        let subtitle = descriptions.count > 1 ? descriptions[1] : ""
        let occurredAt = date(from: subtitle, group: group)
        return Activity(
            id: id + "|" + title + "|" + subtitle,
            title: title,
            subtitle: subtitle,
            group: group,
            imageURL: imageURL,
            occurredAt: occurredAt,
            lockActivityId: firstLockActivityId(in: store)
        )
    }

    private static func firstLockActivityId(in value: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let pattern = #""lockActivityId"\s*:\s*"([a-f0-9]{24})""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func batteryValue(in text: String) -> Int? {
        let digits = text.filter { $0.isNumber }
        return Int(digits)
    }

    private static func date(from subtitle: String, group: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        let timePart = subtitle.components(separatedBy: "•").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? subtitle
        guard let time = formatter.date(from: timePart) else { return nil }
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        var base = Date()
        if group == "Today" {
            base = Date()
        } else if group == "Yesterday" {
            base = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        } else {
            return nil
        }
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: base)
    }
}
