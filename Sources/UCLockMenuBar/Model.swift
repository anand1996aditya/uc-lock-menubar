import Foundation
import SwiftUI

@MainActor
final class LockModel: ObservableObject {
    @Published var config: Config
    @Published var device = DeviceInfo()
    @Published var activities: [Activity] = []
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var isRefreshing = false
    @Published var artworkImage: NSImage?

    var onDoorbell: ((Activity) -> Void)?
    var onDoorbellPhoto: ((Activity, URL) -> Void)?

    private var pollTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var mqtt: UrbanMQTT?
    private var mqttConnected = false
    private var knownIDs: Set<String> = []
    private var artworkSource: String?
    private var shownDoorbellIDs: Set<String> = []

    init() {
        DiagnosticsLog.hardenExistingLogs()
        config = Config.load() ?? Config.template()
        activities = ActivityStore.shared.current
    }

    var needsSetup: Bool { config.token.isEmpty }

    var pendingDoorbell: Activity? {
        activities.first { $0.isDoorbell && $0.isRecent }
    }

    var lastUnlock: Activity? {
        activities.first { $0.isUnlock }
    }

    var lastUnlockPerson: String? {
        guard let unlock = lastUnlock else { return nil }
        let prefix = "unlocked by "
        if unlock.title.lowercased().hasPrefix(prefix) {
            let name = unlock.title.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        return unlock.title
    }

    var lastUnlockMethod: String? {
        guard let method = lastUnlock?.detailText, !method.isEmpty else { return nil }
        return method
    }

    var statusLine: String {
        if let doorbell = pendingDoorbell {
            return "Door bell rung · \(doorbell.timeText) · photo ready"
        }
        if let unlock = lastUnlock {
            let person = unlock.title.replacingOccurrences(of: "Unlocked by ", with: "")
            let method = unlock.detailText
            return method.isEmpty ? "Last unlock \(unlock.timeText) · \(person)"
                                  : "Last unlock \(unlock.timeText) · \(person) · \(method)"
        }
        return "No activity yet"
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
        alertTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkLiveAlert()
                let interval = (self?.mqttConnected == true) ? 120 : 30
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            }
        }
        startMQTT()
    }

    private func startMQTT() {
        guard mqtt == nil, !config.token.isEmpty, !config.userId.isEmpty else { return }
        let client = UrbanMQTT(token: config.token, userId: config.userId)
        client.onWake = { [weak self] in
            Task { await self?.handleWake() }
        }
        client.onState = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.mqttConnected = (state == "subscribed")
                self.logDiag("mqtt \(state)")
            }
        }
        mqtt = client
        client.start()
    }

    private func loadArtwork(_ url: URL?) {
        guard let url else { return }
        guard artworkSource != url.absoluteString else { return }
        artworkSource = url.absoluteString
        Task { [weak self] in
            let processed = await ArtworkProcessor.loadAndProcess(url)
            await MainActor.run {
                if let processed { self?.artworkImage = processed }
            }
        }
    }

    private func handleWake() async {
        logDiag("wake ping")
        try? await Task.sleep(nanoseconds: 300_000_000)
        await checkLiveAlert()
        await refresh()
    }

    private func checkLiveAlert() async {
        guard !config.token.isEmpty else { return }
        let client = APIClient(config: config)
        do {
            let widget = try await client.fetchWidgetAlert(timeout: 6)
            for alert in Parser.widgetAlerts(fromWidget: widget)
            where !shownDoorbellIDs.contains(alert.lockActivityId) {
                shownDoorbellIDs.insert(alert.lockActivityId)
                logDiag("live alert id=\(alert.lockActivityId) at=\(alert.timeText)")
                var activity = Activity(
                    id: "alert|" + alert.lockActivityId,
                    title: "Door bell rung",
                    subtitle: alert.timeText,
                    group: "Today",
                    imageURL: nil,
                    occurredAt: nil,
                    lockActivityId: alert.lockActivityId
                )
                if let photo = await loadDoorbellPhoto(for: activity) {
                    activity = activity.withImageURL(photo)
                }
                onDoorbell?(activity)
                Task { await self.refresh() }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if message.contains("429") {
                logDiag("live alert poll 429, backing off")
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
            } else {
                logDiag("live alert poll error \(message)")
            }
        }
    }

    func refresh() async {
        guard !config.token.isEmpty else {
            errorMessage = "Add your session token in Settings."
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let client = APIClient(config: config)
        do {
            async let deviceObject = client.fetch(RequestBodies.deviceDetails(config))
            async let logsObject = client.fetch(RequestBodies.unlockLogs(config))
            let (deviceJSON, logsJSON) = try await (deviceObject, logsObject)

            let newDevice = Parser.device(from: deviceJSON)
            let newActivities = Parser.activities(from: logsJSON)
            let mergedActivities = ActivityStore.shared.merge(newActivities)

            let hadHistory = !knownIDs.isEmpty
            let newIDs = Set(newActivities.map(\.id))
            let freshDoorbell = newActivities.first { $0.isDoorbell && !knownIDs.contains($0.id) }
            knownIDs = newIDs

            device = newDevice
            loadArtwork(newDevice.artworkURL)
            activities = mergedActivities
            lastUpdated = Date()
            errorMessage = nil
            logDiag("refresh ok activities=\(newActivities.count) battery=\(newDevice.battery.map(String.init) ?? "?")")

            // Preload artwork and the newest photos so rows render without flicker.
            let urls: [URL?] = [newDevice.artworkURL] + newActivities.compactMap(\.imageURL)
            await ImageCache.shared.load(urls)
            objectWillChange.send()
            if hadHistory, let freshDoorbell {
                if let lockActivityId = freshDoorbell.lockActivityId,
                   shownDoorbellIDs.contains(lockActivityId) {
                    logDiag("skip duplicate card id=\(lockActivityId)")
                } else {
                if let lockActivityId = freshDoorbell.lockActivityId {
                    shownDoorbellIDs.insert(lockActivityId)
                }
                logDiag("fresh doorbell id=\(freshDoorbell.id) hasImage=\(freshDoorbell.imageURL != nil)")
                let photoURL = await loadDoorbellPhoto(for: freshDoorbell)
                onDoorbell?(photoURL.map { freshDoorbell.withImageURL($0) } ?? freshDoorbell)
                if photoURL == nil {
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        await self.enrichDoorbellPhoto(freshDoorbell)
                    }
                }
                }
            }
            writeStatus()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            writeStatus()
        }
    }

    func loadDoorbellPhoto(for activity: Activity) async -> URL? {
        let client = APIClient(config: config)
        var activityId = activity.lockActivityId
        if activityId == nil {
            do {
                let widget = try await client.fetchWidgetAlert(timeout: 8)
                activityId = Parser.remoteUnlockAlertId(fromWidget: widget)
            } catch {
                logDiag("photo widget error \(error.localizedDescription)")
            }
        }
        guard let activityId else {
            logDiag("photo no activity id")
            return nil
        }
        do {
            let page = try await client.fetchRemoteUnlockPage(lockActivityId: activityId, timeout: 8)
            guard let url = Parser.unlockPagePhotoURL(fromPage: page) else {
                logDiag("photo page has none id=\(activityId)")
                return nil
            }
            await ImageCache.shared.load([url])
            if ImageCache.shared.image(for: url) != nil {
                logDiag("photo ready id=\(activityId)")
                return url
            }
            logDiag("photo download failed id=\(activityId)")
            return nil
        } catch {
            logDiag("photo page error \(error.localizedDescription)")
            return nil
        }
    }

    func enrichDoorbellPhoto(_ activity: Activity) async {
        if let url = await loadDoorbellPhoto(for: activity) {
            onDoorbellPhoto?(activity, url)
        }
    }

    private func logDiag(_ message: String) {
        DiagnosticsLog.append(message)
    }

    private func writeStatus() {
        let formatter = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "updated": formatter.string(from: lastUpdated ?? Date()),
            "battery": device.battery ?? -1,
            "activities": activities.count,
            "name": device.name,
            "error": errorMessage ?? ""
        ]
        let url = Config.supportDir.appendingPathComponent("status.json")
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            do {
                try FileManager.default.createDirectory(at: Config.supportDir, withIntermediateDirectories: true)
                try data.write(to: url)
                DiagnosticsLog.ensurePrivatePermissions(at: url)
            } catch {
                return
            }
        }
    }

    func save(_ newConfig: Config) {
        config = newConfig
        knownIDs = []
        do {
            try newConfig.save()
        } catch {
            errorMessage = "Could not save settings: \(error.localizedDescription)"
        }
        Task { await refresh() }
    }
}
