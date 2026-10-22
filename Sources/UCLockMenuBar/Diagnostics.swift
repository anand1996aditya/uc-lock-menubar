import Foundation

/// Owner-only diagnostics logging.
///
/// Log files are created with mode 0600 and repaired to 0600 on every append,
/// so files left at 0644 by older builds are fixed in place.
enum DiagnosticsLog {
    static var logURL: URL { Config.supportDir.appendingPathComponent("diagnostics.log") }

    /// Self-tests that exercise deliberate failures set this to keep the real
    /// diagnostics log clean.
    static var suppressWrites = false

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: Config.supportDir, withIntermediateDirectories: true)
    }

    static func ensurePrivatePermissions(at url: URL) {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil,
                               attributes: [.posixPermissions: 0o600])
        }
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func append(_ message: String, to url: URL? = nil) {
        guard !suppressWrites else { return }
        ensureDirectory()
        let target = url ?? logURL
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        ensurePrivatePermissions(at: target)
        if let handle = try? FileHandle(forWritingTo: target) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? line.write(to: target, atomically: true, encoding: .utf8)
            ensurePrivatePermissions(at: target)
        }
        if let size = try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int,
           size > 262_144 {
            try? FileManager.default.removeItem(at: target)
        }
    }

    /// Repairs permissions on files written by older builds (mode 0644).
    static func hardenExistingLogs() {
        ensureDirectory()
        for name in ["diagnostics.log", "status.json"] {
            let url = Config.supportDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                ensurePrivatePermissions(at: url)
            }
        }
    }
}
