import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// `ComicOptimizer --selftest` — builds a synthetic comic and checks the spread logic
/// end to end (archive round-trip, spread detection, redundant-spread removal, page order).
enum SelfCheck {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            do { try await run(); print("selftest OK") }
            catch { print("selftest FAILED: \(error)"); exit(1) }
            finished.signal()
        }
        finished.wait()
        exit(0)
    }

    private static func run() async throws {
        let plain = (0..<8).map { noise(seed: UInt64($0) + 1, w: 600, h: 900) }
        let redundant = join(plain[1], plain[2])          // duplicates the two pages before it
        let unique = join(noise(seed: 90, w: 600, h: 900), noise(seed: 91, w: 600, h: 900))
        let foldout = join(unique, noise(seed: 92, w: 600, h: 900))   // 3× wide

        let source = plain[0...2] + [redundant] + plain[3...7] + [unique, foldout]
        let entries = source.enumerated().map {
            Entry(name: String(format: "p%02d.png", $0.offset), data: png($0.element))
        }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("selftest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("book.cbz")
        try writeCBZ(entries, to: input)

        // The carousel sees the untouched book and bins its first page; afterwards only the
        // spread and the foldout reach the reviewer — never a plain page, never the
        // redundant spread, which the dedup drops on its own.
        var seenByCarousel = 0
        var reviewed: [Int] = []
        let output = try await Pipeline.run(
            input: input, manga: true, useImageOptim: false, log: { _ in },
            preflight: { images in
                seenByCarousel = images.count
                return [0]
            }) { ctx in
                reviewed.append(ctx.index)
                let image = ctx.pages[ctx.index]
                // Honour the suggested cut when there is one, else slice the foldout in thirds.
                let fractions = ctx.suggestedCuts.isEmpty ? [1.0 / 3, 2.0 / 3] : ctx.suggestedCuts
                let xs = ([0] + fractions + [1]).map { Int($0 * CGFloat(image.width)) }
                return .replace((0..<(xs.count - 1)).compactMap {
                    image.cropping(to: CGRect(x: xs[$0], y: 0,
                                              width: xs[$0 + 1] - xs[$0], height: image.height))
                })
            }

        try expect(seenByCarousel == 11, "il carosello doveva vedere 11 pagine, non \(seenByCarousel)")
        try expect(reviewed == [8, 9], "il reviewer doveva vedere le pagine 8 e 9, ha visto \(reviewed)")

        let result = try readArchive(output).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        try expect(result.map(\.name) == ["001.png", "002.png", "003.png", "004.png", "005.png",
                                          "006.png", "007.png", "008.jpg", "009.jpg", "010.jpg",
                                          "011.jpg", "012.jpg"],
                   "nomi inattesi: \(result.map(\.name))")

        // Manga order: the right half of the spread comes first...
        guard let firstHalf = decodeImage(result[7].data), let right = half(unique, left: false)
        else { throw Failure("decodifica fallita") }
        try expect(hamming(dhash(firstHalf), dhash(right)) <= 12, "ordine manga errato sulla tavola doppia")

        // ...and so does the rightmost third of the foldout.
        guard let firstThird = decodeImage(result[9].data),
              let rightThird = foldout.cropping(to: CGRect(x: 2 * foldout.width / 3, y: 0,
                                                           width: foldout.width / 3, height: foldout.height))
        else { throw Failure("decodifica fallita") }
        try expect(hamming(dhash(firstThird), dhash(rightThird)) <= 12, "ordine manga errato sul foldout")
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
