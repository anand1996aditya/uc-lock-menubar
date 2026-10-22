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

        // Family fallback (reads the local family.json if present)
        let members = Family.members()
        check(!members.isEmpty, "family config loaded")
        let unlock = Activity(id: "u1", title: "Unlocked by Alex Kumar", subtitle: "07:21 PM • Via fingerprint",
                              group: "Today", imageURL: nil, occurredAt: Date(), lockActivityId: nil)
        check(Family.avatar(for: unlock) != nil, "family avatar for known name")
        let unknown = Activity(id: "u2", title: "Unlocked by Unknown Person", subtitle: "07:22 PM",
                               group: "Today", imageURL: nil, occurredAt: Date(), lockActivityId: nil)
        check(Family.avatar(for: unknown) == nil, "no avatar for unknown name")

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

        // Menu bar icon loads from the bundle
        if let url = Bundle.main.url(forResource: "MenuIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            check(image.size.width > 0, "menu icon loads")
        } else {
            check(false, "menu icon loads")
        }

        print("UC_UNIT failures=\(failures)")
        return failures
    }
}
