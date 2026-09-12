import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// `ComicOptimizer --selftest` — builds a synthetic comic and checks the spread logic
/// end to end (archive round-trip, spread detection, redundant-spread removal, page order).
enum SelfCheck {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }
        do { try run(); print("selftest OK") } catch { print("selftest FAILED: \(error)"); exit(1) }
        exit(0)
    }

    private static func run() throws {
        let pages = (0..<4).map { noise(seed: UInt64($0) + 1, w: 600, h: 900) }
        let redundant = join(pages[1], pages[2])          // duplicates pages 2+3 → must be dropped
        let unique = join(noise(seed: 90, w: 600, h: 900), noise(seed: 91, w: 600, h: 900))

        let source = [pages[0], pages[1], pages[2], redundant, pages[3], unique]
        let entries = source.enumerated().map { Entry(name: String(format: "p%02d.png", $0.offset), data: png($0.element)) }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("selftest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("book.cbz")
        try writeCBZ(entries, to: input)

        let output = try Pipeline.run(input: input, manga: true, useImageOptim: false) { _ in }
        let result = try readArchive(output).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        try expect(result.count == 6, "atteso 6 pagine, trovate \(result.count)")
        try expect(result.map(\.name) == ["001.png", "002.png", "003.png", "004.png", "005.jpg", "006.jpg"],
                   "nomi inattesi: \(result.map(\.name))")

        // Manga order: the right half of the spread must come first.
        guard let firstHalf = decodeImage(result[4].data), let right = half(unique, left: false)
        else { throw Failure("decodifica fallita") }
        try expect(hamming(dhash(firstHalf), dhash(right)) <= 12, "ordine manga errato")
    }

    // MARK: - helpers

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message) }
    }

    private static func context(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    }

    /// Deterministic blocky noise — distinct enough that dhash separates the pages.
    private static func noise(seed: UInt64, w: Int, h: Int) -> CGImage {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        let ctx = context(w, h)
        for y in 0..<12 {
            for x in 0..<8 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let g = CGFloat((state >> 33) % 256) / 255
                ctx.setFillColor(red: g, green: g, blue: g, alpha: 1)
                ctx.fill(CGRect(x: x * w / 8, y: y * h / 12, width: w / 8, height: h / 12))
            }
        }
        return ctx.makeImage()!
    }

    private static func join(_ left: CGImage, _ right: CGImage) -> CGImage {
        let ctx = context(left.width + right.width, max(left.height, right.height))
        ctx.draw(left, in: CGRect(x: 0, y: 0, width: left.width, height: left.height))
        ctx.draw(right, in: CGRect(x: left.width, y: 0, width: right.width, height: right.height))
        return ctx.makeImage()!
    }

    private static func png(_ image: CGImage) -> Data {
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
}
