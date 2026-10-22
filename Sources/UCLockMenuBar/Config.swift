import Foundation

struct Config: Codable {
    /// Urban Company bearer token. It is never written to config.json; it lives in the macOS Keychain.
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

    static let keychainService = "com.secureu.uclock"
    static let keychainAccount = "bearer-token"
    /// Field name used by older builds that stored the bearer token as plain text.
    static let legacyTokenKey = "token"

    static let apiBase = "https://www.urbanclap.com/api/v2/supply/appliances/getScreenDetails"

    /// Every stored property except `token`. The bearer token must never be encoded.
    enum CodingKeys: String, CodingKey {
        case deviceId, applianceId, userId, cityKey, countryKey, clientKey
        case versionName, versionCode, bundleVersion, sessionId, advertisingId
    }

    init(token: String, deviceId: String, applianceId: String, userId: String,
         cityKey: String, countryKey: String, clientKey: String, versionName: String,
         versionCode: String, bundleVersion: String, sessionId: String, advertisingId: String) {
        self.token = token
        self.deviceId = deviceId
        self.applianceId = applianceId
        self.userId = userId
        self.cityKey = cityKey
        self.countryKey = countryKey
        self.clientKey = clientKey
        self.versionName = versionName
        self.versionCode = versionCode
        self.bundleVersion = bundleVersion
        self.sessionId = sessionId
        self.advertisingId = advertisingId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = ""
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
        applianceId = try container.decodeIfPresent(String.self, forKey: .applianceId) ?? ""
        userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? ""
        cityKey = try container.decodeIfPresent(String.self, forKey: .cityKey) ?? "city_bangalore_v2"
        countryKey = try container.decodeIfPresent(String.self, forKey: .countryKey) ?? "IND"
        clientKey = try container.decodeIfPresent(String.self, forKey: .clientKey) ?? ""
        versionName = try container.decodeIfPresent(String.self, forKey: .versionName) ?? "7.6.87"
        versionCode = try container.decodeIfPresent(String.self, forKey: .versionCode) ?? "726"
        bundleVersion = try container.decodeIfPresent(String.self, forKey: .bundleVersion) ?? "936"
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? UUID().uuidString.lowercased()
        advertisingId = try container.decodeIfPresent(String.self, forKey: .advertisingId) ?? UUID().uuidString.lowercased()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(applianceId, forKey: .applianceId)
        try container.encode(userId, forKey: .userId)
        try container.encode(cityKey, forKey: .cityKey)
        try container.encode(countryKey, forKey: .countryKey)
        try container.encode(clientKey, forKey: .clientKey)
        try container.encode(versionName, forKey: .versionName)
        try container.encode(versionCode, forKey: .versionCode)
        try container.encode(bundleVersion, forKey: .bundleVersion)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(advertisingId, forKey: .advertisingId)
        // token is deliberately not encoded.
    }

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("UC Lock", isDirectory: true)
    }
    static var fileURL: URL { supportDir.appendingPathComponent("config.json") }

    static func load() -> Config? {
        load(from: fileURL, tokenStore: KeychainTokenStore.shared)
    }

    /// Loads the non-secret config from JSON and the bearer token from the secure store.
    ///
    /// The secure store wins. A plain-text token left in an older config.json is
    /// moved to the secure store and blanked from the JSON (one-time migration).
    static func load(from url: URL, tokenStore: SecureTokenStore) -> Config? {
        guard let data = try? Data(contentsOf: url),
              var config = try? JSONDecoder().decode(Config.self, from: data) else { return nil }

        let legacyToken = legacyPlaintextToken(in: data)
        var keychainToken: String?
        do {
            keychainToken = try tokenStore.read(service: keychainService, account: keychainAccount)
        } catch {
            DiagnosticsLog.append("keychain read failed: \(error.localizedDescription)")
        }

        if let token = keychainToken, !token.isEmpty {
            config.token = token
            if !legacyToken.isEmpty {
                try? config.save(to: url, tokenStore: tokenStore)
                DiagnosticsLog.append("preferred Keychain bearer token and removed legacy plaintext copy")
            }
        } else if !legacyToken.isEmpty {
            config.token = legacyToken
            do {
                try config.save(to: url, tokenStore: tokenStore)
                DiagnosticsLog.append("migrated bearer token to Keychain")
            } catch {
                // Keep the legacy copy so the session still works and migration can retry.
                DiagnosticsLog.append("keychain migration failed; kept legacy copy: \(error.localizedDescription)")
            }
        }
        return config
    }

    func save() throws {
        try save(to: Config.fileURL, tokenStore: KeychainTokenStore.shared)
    }

    /// Saves the non-secret config to JSON and the bearer token to the secure store.
    /// The JSON never contains the token.
    func save(to url: URL = Config.fileURL, tokenStore: SecureTokenStore = KeychainTokenStore.shared) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        if token.isEmpty {
            try tokenStore.delete(service: Config.keychainService, account: Config.keychainAccount)
        } else {
            try tokenStore.write(token, service: Config.keychainService, account: Config.keychainAccount)
        }
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func legacyPlaintextToken(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object[legacyTokenKey] as? String else { return "" }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
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
