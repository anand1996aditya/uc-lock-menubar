import Foundation

struct StoredActivity: Codable {
    var id: String
    var title: String
    var subtitle: String
    var group: String
    var imageURL: String?
    var occurredAt: Date?
    var lockActivityId: String?
    var storedAt: Date

    init(_ activity: Activity, now: Date = Date()) {
        id = activity.id
        title = activity.title
        subtitle = activity.subtitle
        group = activity.group
        imageURL = activity.imageURL?.absoluteString
        occurredAt = activity.occurredAt
        lockActivityId = activity.lockActivityId
        storedAt = now
    }

    var effectiveDate: Date { occurredAt ?? storedAt }

    func activity() -> Activity {
        Activity(id: id, title: title, subtitle: subtitle, group: group,
                 imageURL: imageURL.flatMap(URL.init(string:)),
                 occurredAt: occurredAt, lockActivityId: lockActivityId)
    }
}

@MainActor
final class ActivityStore {
    static let shared = ActivityStore()

    private let fileURL: URL
    private let retention: TimeInterval = 72 * 3600
    private let maximumEntries = 300
    private var entries: [StoredActivity] = []

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Config.supportDir.appendingPathComponent("activity-history.json")
        load()
    }

    var current: [Activity] {
        entries.sorted { $0.effectiveDate > $1.effectiveDate }.map { $0.activity() }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([StoredActivity].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-retention)
        entries = list.filter { $0.effectiveDate > cutoff }
    }

    func merge(_ fresh: [Activity], now: Date = Date()) -> [Activity] {
        var map: [String: StoredActivity] = [:]
        for entry in entries { map[entry.id] = entry }
        for activity in fresh { map[activity.id] = StoredActivity(activity, now: now) }

        let cutoff = now.addingTimeInterval(-retention)
        entries = map.values
            .filter { $0.effectiveDate > cutoff }
            .sorted { $0.effectiveDate > $1.effectiveDate }
        if entries.count > maximumEntries {
            entries = Array(entries.prefix(maximumEntries))
        }
        save()

        var result = fresh
        let freshIDs = Set(fresh.map(\.id))
        result.append(contentsOf: entries.filter { !freshIDs.contains($0.id) }.map { $0.activity() })
        return result
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
    }

    func clear() {
        entries = []
        save()
    }
}
