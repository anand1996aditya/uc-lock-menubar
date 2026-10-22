import Foundation
import AppKit

@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private(set) var images: [URL: NSImage] = [:]

    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        return images[url]
    }

    func load(_ urls: [URL?]) async {
        let pending = urls.compactMap { $0 }.filter { images[$0] == nil }
        await withTaskGroup(of: (URL, NSImage?).self) { group in
            for url in pending.prefix(8) {
                group.addTask {
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return (url, nil) }
                        return (url, NSImage(data: data))
                    } catch {
                        return (url, nil)
                    }
                }
            }
            for await (url, image) in group {
                if let image { images[url] = image }
            }
        }
    }
}
