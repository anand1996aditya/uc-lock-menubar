import Foundation

struct Config: Codable {
    var token: String
    var deviceId: String
    var applianceId: String
    var userId: String
    var cityKey: String
    var countryKey: String
    var clientKey: String
    var versionName: String
    var versionCode: String
    var bundleVersion: String
    var sessionId: String
    var advertisingId: String

    static let apiBase = "https://www.urbanclap.com/api/v2/supply/appliances/getScreenDetails"

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("UC Lock", isDirectory: true)
    }
    static var fileURL: URL { supportDir.appendingPathComponent("config.json") }

    static func load() -> Config? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Config.supportDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: Config.fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.fileURL.path)
    }

    static func isValidIdentifier(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 && trimmed.count <= 32 else { return false }
        return trimmed.allSatisfy { $0.isHexDigit }
    }

    static func template() -> Config {
        Config(
            token: "",
            deviceId: "",
            applianceId: "",
            userId: "",
            cityKey: "city_bangalore_v2",
            countryKey: "IND",
            clientKey: "",
            versionName: "7.6.87",
            versionCode: "726",
            bundleVersion: "936",
            sessionId: UUID().uuidString.lowercased(),
            advertisingId: UUID().uuidString.lowercased()
        )
    }
}

struct RequestBodies {
    static func deviceDetails(_ c: Config) -> [String: Any] {
        [
            "applianceType": "SMART_LOCK_GEN3",
            "flowType": "details",
            "screenName": "device_details",
            "deviceType": "LOCK",
            "userId": c.userId,
            "applianceId": c.applianceId,
            "launchMode": "NEW_TASK",
            "countryKey": c.countryKey,
            "cityKey": c.cityKey,
            "city_key": c.cityKey,
            "device_id": c.deviceId,
            "device_os": "android",
            "device_type": "android",
            "version": "1",
            "version_code": c.versionCode,
            "version_name": c.versionName
        ]
    }

    static func unlockLogs(_ c: Config) -> [String: Any] {
        [
            "applianceType": "SMART_LOCK_GEN3",
            "unlockLogsEnumIndex": 0,
            "userId": c.userId,
            "applianceId": c.applianceId,
            "flowType": "alerts",
            "screenName": "unlock_logs_page",
            "deviceType": "LOCK",
            "countryKey": c.countryKey,
            "cityKey": c.cityKey,
            "city_key": c.cityKey,
            "device_id": c.deviceId,
            "device_os": "android",
            "device_type": "android",
            "version": "1",
            "version_code": c.versionCode,
            "version_name": c.versionName
        ]
    }

    static func widgetAlert(_ c: Config) -> [String: Any] {
        [
            "cityKey": c.cityKey,
            "subFlowId": "requestStateWidget",
            "city_key": c.cityKey,
            "device_id": c.deviceId,
            "device_os": "android",
            "device_type": "android",
            "version": "1",
            "version_code": c.versionCode,
            "version_name": c.versionName
        ]
    }

    static func remoteUnlockPage(_ c: Config, lockActivityId: String) -> [String: Any] {
        [
            "applianceType": "SMART_LOCK_GEN3",
            "userId": c.userId,
            "applianceId": c.applianceId,
            "flowType": "alerts",
            "screenName": "remote_unlock_page",
            "deviceType": "LOCK",
            "lockActivityId": lockActivityId,
            "countryKey": c.countryKey,
            "cityKey": c.cityKey,
            "city_key": c.cityKey,
            "device_id": c.deviceId,
            "device_os": "android",
            "device_type": "android",
            "version": "1",
            "version_code": c.versionCode,
            "version_name": c.versionName
        ]
    }

    static func headers(_ c: Config) -> [String: String] {
        [
            "X-os-version": "Android SDK: 35 (15)",
            "X-device-os": "android",
            "x-preferred-language": "english",
            "accept-language": "en-IN;q=1",
            "X-Session-ID": c.sessionId,
            "X-advertising-id": c.advertisingId,
            "X-accessibility": "false",
            "accept": "application/json",
            "Authorization": "Bearer \(c.token)",
            "X-version-name": c.versionName,
            "X-version-code": c.versionCode,
            "x-brand-key": "urbanCompany",
            "X-client-key": c.clientKey,
            "X-device-id": c.deviceId,
            "react-bundle-version": c.bundleVersion,
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "Dalvik/2.1.0 (Linux; U; Android 15; sdk_gphone64_arm64 Build/AE3A.240806.043)"
        ]
    }
}
