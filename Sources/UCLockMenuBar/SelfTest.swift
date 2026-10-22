import AppKit

enum UCLockSelfTest {
    @MainActor
    static func run() -> Int {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            if condition { print("PASS \(name)") }
            else { failures += 1; print("FAIL \(name)") }
        }

        // Config template encodes and decodes
        let template = Config.template()
        if let data = try? JSONEncoder().encode(template),
           let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            check(decoded.token.isEmpty, "config empty token")
            check(decoded.sessionId == template.sessionId, "config round trip")
        } else {
            check(false, "config round trip")
        }

        // Identifier validation
        check(Config.isValidIdentifier("68e189e68c3a9c00237424a4"), "hex appliance id")
        check(!Config.isValidIdentifier("zzzzzzzzzz"), "reject non-hex id")
        check(!Config.isValidIdentifier("abc"), "reject short id")

        // Activity parsing from a fake server response
        let fixture: [String: Any] = [
            "success": [
                "data": [
                    "dataStore": [
                        "timeStampHeading1": [
                            "items": [[ "data": [ "adsTextStack": [ "items": [[ "data": [ "text": "Today" ] ]] ] ] ]]
                        ],
                        "activity_1": [
                            "items": [
                                [ "data": [ "adsTextStack": [ "items": [
                                    [ "type": "description", "data": [ "text": "Door bell rung" ] ],
                                    [ "type": "description", "data": [ "text": "03:17 PM" ] ]
                                ] ] ] ],
                                [ "data": [ "mediaContent": [ "props": [ "image": [ "remoteSrcExternal": [ "url": "https://example.com/photo.jpg" ] ] ] ] ] ]
                            ]
                        ]
                    ],
                    "layout": [ "widgets": [ "default": [ [ "id": "timeStampHeading1" ], [ "id": "activity_1" ] ] ] ]
                ]
            ]
        ]
        let activities = Parser.activities(from: fixture)
        check(activities.count == 1, "activity count")
        check(activities.first?.title == "Door bell rung", "activity title")
        check(activities.first?.isDoorbell == true, "activity doorbell")
        check(activities.first?.imageURL?.absoluteString == "https://example.com/photo.jpg", "activity photo")
        check(activities.first?.timeText == "03:17 PM", "activity time")
        check(activities.first?.occurredAt != nil, "activity date parsed")

        // Device parsing
        let deviceFixture: [String: Any] = [
            "success": [ "data": [ "dataStore": [
                "applianceDetailsCard": [ "textStack": [ "items": [
                    [ "data": [ "text": "Example smart lock" ] ],
                    [ "data": [ "tags": [ [ "text": "10%" ] ] ] ]
                ] ] ]
            ], "layout": [ "widgets": [ "default": [] ] ] ] ]
        ]
        let device = Parser.device(from: deviceFixture)
        check(device.name == "Example smart lock", "device name")
        check(device.battery == 10, "device battery")

        // Family matching uses a temporary store, never the user's local file.
        let familyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("uc-family-test-\(UUID().uuidString).json")
        let familyJSON = #"{"members":[{"name":"Alex","aliases":["alex"],"role":"Guest","image":"alex.jpg"}]}"#
        try? familyJSON.write(to: familyURL, atomically: true, encoding: .utf8)
        check(Family.member(for: "Unlocked by Alex Kumar", at: familyURL) != nil, "family alias matches")
        check(Family.member(for: "Unlocked by Unknown Person", at: familyURL) == nil, "family alias misses")
        try? FileManager.default.removeItem(at: familyURL)

        // Freshness window
        let fresh = Activity(id: "d1", title: "Door bell rung", subtitle: "07:00 PM", group: "Today",
                             imageURL: nil, occurredAt: Date().addingTimeInterval(-300), lockActivityId: nil)
        let stale = Activity(id: "d2", title: "Door bell rung", subtitle: "03:00 PM", group: "Today",
                             imageURL: nil, occurredAt: Date().addingTimeInterval(-3600), lockActivityId: nil)
        check(fresh.isRecent, "fresh doorbell")
        check(!stale.isRecent, "stale doorbell")

        // Last unlock detail extraction
        let model = LockModel()
        model.activities = [
            Activity(id: "unlock", title: "Unlocked by Alex Kumar",
                     subtitle: "07:21 PM • Via fingerprint", group: "Today",
                     imageURL: nil, occurredAt: Date(), lockActivityId: nil)
        ]
        check(model.lastUnlockPerson == "Alex Kumar", "last unlock person")
        check(model.lastUnlockMethod == "Via fingerprint", "last unlock method")

        // Activity store: merge, persistence and 72 hour pruning
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("uc-activity-test-\(UUID().uuidString).json")
        let store = ActivityStore(fileURL: storeURL)
        let storedFresh = Activity(id: "a1", title: "Door bell rung", subtitle: "08:00 PM",
                                   group: "Today", imageURL: nil, occurredAt: Date(),
                                   lockActivityId: nil)
        let merged = store.merge([storedFresh])
        check(merged.count == 1, "activity store merge")
        let reloaded = ActivityStore(fileURL: storeURL)
        check(reloaded.current.count == 1, "activity store persistence")
        let old = Activity(id: "old", title: "Door bell rung", subtitle: "08:00 PM",
                           group: "Today", imageURL: nil,
                           occurredAt: Date().addingTimeInterval(-80 * 3600),
                           lockActivityId: nil)
        _ = store.merge([old])
        check(!store.current.contains { $0.id == "old" }, "activity store prunes old entries")
        store.clear()
        try? FileManager.default.removeItem(at: storeURL)

        // Studio background removal keeps the lock and clears the white margins
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 60, pixelsHigh: 60,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)
        if let rep {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 60, height: 60).fill()
            NSColor.black.setFill()
            NSRect(x: 20, y: 18, width: 20, height: 26).fill()
            NSGraphicsContext.restoreGraphicsState()
            let source = NSImage(size: NSSize(width: 60, height: 60))
            source.addRepresentation(rep)
            if let cleaned = ArtworkProcessor.process(source),
               let data = cleaned.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: data) {
                check(cleaned.size.width < 60 || cleaned.size.height < 60, "artwork background removed")
                check((bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.alphaComponent ?? 0) > 0.5,
                      "artwork subject kept")
            } else {
                check(false, "artwork background removed")
            }
        }

        // Menu bar icon loads from the bundle
        if let url = Bundle.main.url(forResource: "MenuIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            check(image.size.width > 0, "menu icon loads")
        } else {
            check(false, "menu icon loads")
        }

        // Keychain-backed bearer token storage, migration and log permissions
        tokenStorageTests(check)

        print("UC_UNIT failures=\(failures)")
        return failures
    }

    /// Exercises Keychain-backed storage, one-time migration and log permissions
    /// with an in-memory token store. The real Keychain is never touched here.
    private static func tokenStorageTests(_ check: (Bool, String) -> Void) {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("uc-storage-test-\(UUID().uuidString)", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.json")

        func writeLegacyJSON(_ token: String) {
            let legacy: [String: Any] = [
                "token": token,
                "deviceId": "2ef0c584868e29bd",
                "applianceId": "68e189e68c3a9c00237424a4",
                "userId": "67247d57ad26302e38c76d43",
                "cityKey": "city_bangalore_v2",
                "countryKey": "IND",
                "clientKey": "",
                "versionName": "7.6.87",
                "versionCode": "726",
                "bundleVersion": "936",
                "sessionId": "session-1",
                "advertisingId": "advertising-1"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: legacy) {
                try? data.write(to: configURL)
            }
        }

        func rawJSON() -> [String: Any] {
            guard let data = try? Data(contentsOf: configURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            return object
        }

        let key = (service: Config.keychainService, account: Config.keychainAccount)

        // Deliberate failure paths must not write to the real diagnostics log.
        DiagnosticsLog.suppressWrites = true
        defer { DiagnosticsLog.suppressWrites = false }

        // Legacy plain-text token moves to the secure store and leaves the JSON.
        writeLegacyJSON("legacy-bearer-token")
        let store = InMemoryTokenStore()
        let migrated = Config.load(from: configURL, tokenStore: store)
        check(migrated?.token == "legacy-bearer-token", "legacy token migrates in memory")
        check(store.value(service: key.service, account: key.account) == "legacy-bearer-token",
              "legacy token stored in secure store")
        check(rawJSON()["token"] == nil, "legacy token removed from config json")
        check(migrated?.applianceId == "68e189e68c3a9c00237424a4", "migration preserves appliance id")
        check(migrated?.cityKey == "city_bangalore_v2", "migration preserves city key")

        // The secure store wins over a stale plain-text copy.
        writeLegacyJSON("stale-json-token")
        let preferred = Config.load(from: configURL, tokenStore: store)
        check(preferred?.token == "legacy-bearer-token", "secure store preferred over legacy json")
        check(rawJSON()["token"] == nil, "stale legacy copy scrubbed when secure store wins")

        // A failed secure-store write keeps the legacy copy and a usable session.
        writeLegacyJSON("cannot-migrate-token")
        let brokenStore = InMemoryTokenStore()
        brokenStore.failWrite = true
        let fallback = Config.load(from: configURL, tokenStore: brokenStore)
        check(fallback?.token == "cannot-migrate-token", "session works when secure store write fails")
        check(rawJSON()["token"] as? String == "cannot-migrate-token",
              "legacy copy kept when migration fails")

        // Saving writes the token to the store and never to the JSON.
        var saved = fallback ?? Config.template()
        saved.token = "new-bearer-token"
        let saveStore = InMemoryTokenStore()
        var saveSucceeded = false
        do {
            try saved.save(to: configURL, tokenStore: saveStore)
            saveSucceeded = true
        } catch {
            saveSucceeded = false
        }
        check(saveSucceeded, "config save succeeds")
        check(saveStore.value(service: key.service, account: key.account) == "new-bearer-token",
              "save writes token to secure store")
        check(rawJSON()["token"] == nil, "save keeps token out of config json")
        let reloaded = Config.load(from: configURL, tokenStore: saveStore)
        check(reloaded?.token == "new-bearer-token", "token reloads from secure store")

        // A failed secure-store write makes save fail without writing the JSON.
        let failingStore = InMemoryTokenStore()
        failingStore.failWrite = true
        var failingConfig = reloaded ?? Config.template()
        failingConfig.token = "will-fail"
        var saveFailed = false
        do {
            try failingConfig.save(to: configURL, tokenStore: failingStore)
        } catch {
            saveFailed = true
        }
        check(saveFailed, "save reports secure store failure")

        // Signing out clears the stored token.
        var signedOut = reloaded ?? Config.template()
        signedOut.token = ""
        try? signedOut.save(to: configURL, tokenStore: saveStore)
        check(saveStore.value(service: key.service, account: key.account) == nil,
              "sign out removes token from secure store")
        check(rawJSON()["token"] == nil, "sign out keeps token out of config json")

        // A Keychain read error does not crash loading.
        let unreadable = InMemoryTokenStore()
        unreadable.failRead = true
        check(Config.load(from: configURL, tokenStore: unreadable) != nil,
              "config loads when secure store read fails")

        // Diagnostics logs and status files are owner-only.
        DiagnosticsLog.suppressWrites = false
        let logURL = directory.appendingPathComponent("diagnostics.log")
        DiagnosticsLog.append("permission test", to: logURL)
        check(fileMode(of: logURL) == 0o600, "diagnostics log created with 0600")
        try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: logURL.path)
        DiagnosticsLog.append("permission repair", to: logURL)
        check(fileMode(of: logURL) == 0o600, "leftover log repaired to 0600")
        let statusURL = directory.appendingPathComponent("status.json")
        try? "{}".write(to: statusURL, atomically: true, encoding: .utf8)
        try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: statusURL.path)
        DiagnosticsLog.ensurePrivatePermissions(at: statusURL)
        check(fileMode(of: statusURL) == 0o600, "status file repaired to 0600")
    }

    private static func fileMode(of url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.posixPermissions] as? NSNumber)?.intValue
    }
}
