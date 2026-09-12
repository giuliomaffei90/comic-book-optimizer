import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff", "heic", "avif"]

func isImageName(_ name: String) -> Bool {
    let base = (name as NSString).lastPathComponent
    guard !base.hasPrefix("."), !name.contains("__MACOSX") else { return false }
    return imageExtensions.contains((name as NSString).pathExtension.lowercased())
}

func decodeImage(_ data: Data) -> CGImage? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
}

func encodeJPEG(_ image: CGImage, quality: CGFloat) -> Data? {
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
}

/// Left or right half of a double-page spread.
func half(_ image: CGImage, left: Bool) -> CGImage? {
    let w = image.width / 2
    return image.cropping(to: CGRect(x: left ? 0 : image.width - w, y: 0, width: w, height: image.height))
}

/// Downscales to fit inside the box; returns the original if it already fits.
func fit(_ image: CGImage, maxW: Int, maxH: Int) -> CGImage {
    let scale = min(CGFloat(maxW) / CGFloat(image.width), CGFloat(maxH) / CGFloat(image.height))
    guard scale < 1 else { return image }
    let w = Int((CGFloat(image.width) * scale).rounded()), h = Int((CGFloat(image.height) * scale).rounded())
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return image }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage() ?? image
}

/// 64-bit difference hash — resolution independent, so it can compare a spread half
/// against an already-split page stored at a different size.
func dhash(_ image: CGImage) -> UInt64 {
    let w = 9, h = 8
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                              space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGImageAlphaInfo.none.rawValue),
          let px = ctx.data
    else { return 0 }
    ctx.interpolationQuality = .low
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = px.bindMemory(to: UInt8.self, capacity: w * h)
    var hash: UInt64 = 0, bit = 0
    for y in 0..<h {
        for x in 0..<(w - 1) {
            if p[y * w + x] > p[y * w + x + 1] { hash |= 1 << UInt64(bit) }
            bit += 1
        }
    }
    return hash
}

func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }
