import AppKit

enum ArtworkProcessor {
    private static func isLightBackground(r: Int, g: Int, b: Int) -> Bool {
        let maximum = max(r, max(g, b))
        let minimum = min(r, min(g, b))
        let luminance = (r + g + b) / 3
        let saturation = maximum == 0 ? 0.0 : Double(maximum - minimum) / Double(maximum)
        return luminance >= 210 && saturation <= 0.12
    }

    /// Removes the light studio background from a product cut-out. The removal
    /// starts from the image border and also clears large enclosed light areas,
    /// which handles gradients and shadows. Small white details stay.
    static func process(_ image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = min(cgImage.width, 700)
        let height = max(1, Int(Double(cgImage.height) * Double(width) / Double(max(1, cgImage.width))))

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func isBackground(_ index: Int) -> Bool {
            let offset = index * 4
            if pixels[offset + 3] == 0 { return true }
            return isLightBackground(r: Int(pixels[offset]), g: Int(pixels[offset + 1]), b: Int(pixels[offset + 2]))
        }

        let minimumBackgroundArea = max(64, (width * height) / 100)
        var visited = [Bool](repeating: false, count: width * height)

        for start in 0..<(width * height) where !visited[start] && isBackground(start) {
            var stack = [start]
            visited[start] = true
            var component: [Int] = []
            var touchesBorder = false
            while let index = stack.popLast() {
                component.append(index)
                let x = index % width, y = index / width
                if x == 0 || y == 0 || x == width - 1 || y == height - 1 { touchesBorder = true }
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let neighbour = ny * width + nx
                    if !visited[neighbour] && isBackground(neighbour) {
                        visited[neighbour] = true
                        stack.append(neighbour)
                    }
                }
            }
            if touchesBorder || component.count >= minimumBackgroundArea {
                for index in component {
                    let offset = index * 4
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 0
                    pixels[offset + 3] = 0
                }
            }
        }

        // Soften the alpha edge with one pass of neighbour averaging.
        var softened = pixels
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let alpha = pixels[index * 4 + 3]
                guard alpha > 0 else { continue }
                let neighbours = [(y - 1) * width + x, (y + 1) * width + x,
                                  y * width + x - 1, y * width + x + 1]
                if neighbours.contains(where: { pixels[$0 * 4 + 3] == 0 }) {
                    let average = neighbours.map { Int(pixels[$0 * 4 + 3]) }.reduce(0, +) / 4
                    let newAlpha = max(0, min(Int(alpha), average))
                    if newAlpha == 0 {
                        softened[index * 4] = 0
                        softened[index * 4 + 1] = 0
                        softened[index * 4 + 2] = 0
                    } else {
                        let scale = Double(newAlpha) / Double(max(1, Int(alpha)))
                        for channel in 0..<3 {
                            softened[index * 4 + channel] = UInt8(min(255, Int(Double(softened[index * 4 + channel]) * scale)))
                        }
                    }
                    softened[index * 4 + 3] = UInt8(newAlpha)
                }
            }
        }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where softened[(y * width + x) * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        guard let output = CGContext(data: &softened, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let fullImage = output.makeImage(),
              let cropped = fullImage.cropping(to: CGRect(x: minX, y: minY,
                                                          width: maxX - minX + 1,
                                                          height: maxY - minY + 1)) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    static func loadAndProcess(_ url: URL) async -> NSImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data) else { return nil }
        let processed = process(image)
        if ProcessInfo.processInfo.environment["UCLOCK_ARTWORK_DEBUG"] != nil {
            try? data.write(to: URL(fileURLWithPath: "/tmp/art-orig.png"))
            if let processed, let tiff = processed.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "/tmp/art-proc.png"))
            }
        }
        return processed
    }
}
