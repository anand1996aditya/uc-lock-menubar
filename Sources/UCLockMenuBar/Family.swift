import AppKit

enum Family {
    struct Member: Decodable {
        let name: String
        let aliases: [String]
        let role: String?
        let image: String
    }

    private struct Store: Decodable {
        let members: [Member]
    }

    static var storeURL: URL {
        Config.supportDir.appendingPathComponent("family.json")
    }

    static func members() -> [Member] {
        guard let data = try? Data(contentsOf: storeURL),
              let store = try? JSONDecoder().decode(Store.self, from: data) else { return [] }
        return store.members
    }

    static func member(for text: String) -> Member? {
        let lower = text.lowercased()
        return members().first { member in
            member.aliases.contains { lower.contains($0.lowercased()) }
        }
    }

    static func image(for member: Member) -> NSImage? {
        NSImage(contentsOf: Config.supportDir.appendingPathComponent(member.image))
    }

    static func avatar(for activity: Activity) -> NSImage? {
        guard activity.imageURL == nil,
              let member = member(for: activity.title) else { return nil }
        return image(for: member)
    }
}
