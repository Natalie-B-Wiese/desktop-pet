import AppKit

/// Recolors the pixel-art pet by swapping its pure red, green and blue pixels.
enum PetRenderer {
    private static var sources: [String: CGImage] = [:]

    private static func source(for character: PetCharacter) -> CGImage {
        if let image = sources[character.imageName] { return image }
        let name = character.imageName
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { fatalError("\(name).png is missing from the app bundle") }
        sources[name] = image
        return image
    }

    /// Which of the three recolorable parts (red, green, blue) the character's image actually contains.
    static func usedSlots(for character: PetCharacter) -> [Bool] {
        let source = source(for: character)
        var used = [false, false, false]
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] == 255 {
            switch (pixels[i], pixels[i + 1], pixels[i + 2]) {
            case (200..., ..<56, ..<56): used[0] = true
            case (..<56, 200..., ..<56): used[1] = true
            case (..<56, ..<56, 200...): used[2] = true
            default: break
            }
        }
        return used
    }

    /// Every character's image is the same size, so the first one stands for them all.
    static var pixelSize: CGSize {
        let source = source(for: PetCharacter.all[0])
        return CGSize(width: source.width, height: source.height)
    }

    static func render(_ character: PetCharacter, _ palette: PetPalette) -> NSImage {
        let source = source(for: character)
        let width = source.width
        let height = source.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        let result: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            context.interpolationQuality = .none
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

            let main = rgb(palette.main)
            let secondary = rgb(palette.secondary)
            let detail = rgb(palette.detail)

            for i in stride(from: 0, to: buffer.count, by: 4) {
                guard buffer[i + 3] == 255 else { continue } // skip transparent pixels
                let r = buffer[i], g = buffer[i + 1], b = buffer[i + 2]
                let replacement: (UInt8, UInt8, UInt8)?
                switch (r, g, b) {
                case (200..., ..<56, ..<56): replacement = main
                case (..<56, 200..., ..<56): replacement = secondary
                case (..<56, ..<56, 200...): replacement = detail
                default: replacement = nil // black, white and any other color stay as-is
                }
                if let (nr, ng, nb) = replacement {
                    buffer[i] = nr
                    buffer[i + 1] = ng
                    buffer[i + 2] = nb
                }
            }
            return context.makeImage()
        }

        return NSImage(cgImage: result ?? source, size: pixelSize)
    }

    private static func rgb(_ color: NSColor) -> (UInt8, UInt8, UInt8) {
        let c = color.usingColorSpace(.sRGB) ?? color
        return (
            UInt8((c.redComponent * 255).rounded()),
            UInt8((c.greenComponent * 255).rounded()),
            UInt8((c.blueComponent * 255).rounded())
        )
    }
}
