import AppKit
import Foundation
import SwiftUI

enum SelfTest {
    @MainActor
    static func run() {
        Task { @MainActor in
            guard let config = Config.load() else {
                print("NO_CONFIG at \(Config.fileURL.path)")
                exit(2)
            }
            let client = APIClient(config: config)
            do {
                async let deviceObject = client.fetch(RequestBodies.deviceDetails(config))
                async let logsObject = client.fetch(RequestBodies.unlockLogs(config))
                let (deviceJSON, logsJSON) = try await (deviceObject, logsObject)
                let device = Parser.device(from: deviceJSON)
                let activities = Parser.activities(from: logsJSON)
                let pending = activities.first(where: { $0.isDoorbell && $0.isRecent })?.subtitle ?? "none"
                print("OK name=\"\(device.name)\" battery=\(device.battery.map(String.init) ?? "?") activities=\(activities.count) pending=\(pending) first=\"\(activities.first?.title ?? "-")\"")
                exit(0)
            } catch {
                print("ERROR \(error.localizedDescription)")
                exit(1)
            }
        }
        RunLoop.main.run()
        exit(3)
    }
}

enum Snapshot {
    @MainActor
    static func run(path: String) {
        Task { @MainActor in
            let model = LockModel()
            await model.refresh()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let view = PopoverView(model: model, staticMode: true)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                print("SNAPSHOT \(path) \(Int(image.size.width))x\(Int(image.size.height))")
                exit(0)
            }
            print("SNAPSHOT_FAILED")
            exit(1)
        }
        RunLoop.main.run()
        exit(3)
    }
}

enum AlertParserTest {
    @MainActor
    static func run(path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("ALERT_FAIL read")
            exit(1)
        }
        let alerts = Parser.widgetAlerts(fromWidget: object)
        print("ALERT_COUNT \(alerts.count)")
        for alert in alerts {
            print("ALERT id=\(alert.lockActivityId) time=\(alert.timeText) message=\(alert.message)")
        }
        exit(alerts.isEmpty ? 2 : 0)
    }
}

enum PhotoSelftest {
    @MainActor
    static func run() {
        Task { @MainActor in
            let model = LockModel()
            await model.refresh()
            guard let activity = model.activities.first(where: { $0.isDoorbell }) else {
                print("PHOTO_FAIL no doorbell activity")
                exit(1)
            }
            print("PHOTO_ACTIVITY lid=\(activity.lockActivityId ?? "nil") hasImage=\(activity.imageURL != nil)")
            model.onDoorbellPhoto = { _, url in
                print("PHOTO_OK \(url.absoluteString.prefix(90))")
                exit(0)
            }
            await model.enrichDoorbellPhoto(activity)
            print("PHOTO_FAIL no callback")
            exit(2)
        }
        RunLoop.main.run()
        exit(3)
    }
}

enum DoorbellSnapshot {
    @MainActor
    static func run(path: String) {
        Task { @MainActor in
            let model = LockModel()
            await model.refresh()
            let activity = model.activities.first { $0.isDoorbell } ?? Activity(
                id: "sample", title: "Door bell rung", subtitle: "12:34 PM", group: "Today",
                imageURL: nil, occurredAt: Date(), lockActivityId: nil
            )
            let view = DoorbellCardView(model: DoorbellCardModel(activity: activity), onOpen: {}, onDismiss: {})
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                print("DOORBELL_SNAPSHOT \(path) \(Int(image.size.width))x\(Int(image.size.height))")
                exit(0)
            }
            print("DOORBELL_SNAPSHOT_FAILED")
            exit(1)
        }
        RunLoop.main.run()
        exit(3)
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--selftest-alert") {
    let path = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "/tmp/widget_alert.json"
    MainActor.assumeIsolated { AlertParserTest.run(path: path) }
} else if CommandLine.arguments.contains("--selftest-photo") {
    MainActor.assumeIsolated { PhotoSelftest.run() }
} else if CommandLine.arguments.contains("--selftest") {
    MainActor.assumeIsolated {
        let failures = UCLockSelfTest.run()
        exit(failures == 0 ? 0 : 1)
    }
} else if CommandLine.arguments.contains("--selftest-old") {
    MainActor.assumeIsolated { SelfTest.run() }
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot-doorbell") {
    let path = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "/tmp/uc-doorbell.png"
    MainActor.assumeIsolated { DoorbellSnapshot.run(path: path) }
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let path = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "/tmp/uc-lock-snapshot.png"
    MainActor.assumeIsolated { Snapshot.run(path: path) }
} else {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
