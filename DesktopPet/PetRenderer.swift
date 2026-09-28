import AppKit

/// Recolors the pixel-art pet by swapping its pure red, green and blue pixels.
enum PetRenderer {
    private static let source: CGImage = {
        guard let url = Bundle.main.url(forResource: "pet", withExtension: "png"),
              let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { fatalError("pet.png is missing from the app bundle") }
        return image
    }()

    static var pixelSize: CGSize {
        CGSize(width: source.width, height: source.height)
    }

    static func render(_ palette: PetPalette) -> NSImage {
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
