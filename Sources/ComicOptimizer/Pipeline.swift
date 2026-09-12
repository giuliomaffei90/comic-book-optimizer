import Foundation
import CoreGraphics

enum ImageOptim {
    static let path = "/Applications/ImageOptim.app/Contents/MacOS/ImageOptim"
    static var available: Bool { FileManager.default.isExecutableFile(atPath: path) }

    /// ImageOptim optimises the files in place using its own saved preferences.
    static func run(files: [URL]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = files.map(\.path)
        try p.run()
        p.waitUntilExit()
    }
}

private struct Page {
    var image: CGImage
    var data: Data
    var ext: String
    var hash: UInt64
    var isDouble = false
    var drop = false
}

enum Pipeline {
    static let maxW = 2048, maxH = 2732      // iPad Pro 12.9" native resolution
    static let jpegQuality: CGFloat = 0.81   // same as the ImageOptim JPEG slider
    static let hashThreshold = 12            // out of 64 bits
    static let doubleRatioFactor: CGFloat = 1.5

    static func run(input: URL, manga: Bool, useImageOptim: Bool, log: (String) -> Void) throws -> URL {
        var entries = try load(input)
        entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !entries.isEmpty else { throw ArchiveError.noImages }
        log("\(entries.count) immagini trovate")

        var pages: [Page] = entries.compactMap {
            guard let img = decodeImage($0.data) else { return nil }
            return Page(image: img, data: $0.data, ext: ($0.name as NSString).pathExtension.lowercased(),
                        hash: dhash(img))
        }
        guard !pages.isEmpty else { throw ArchiveError.noImages }

        // A spread is a page far wider (relative to its height) than the book's norm.
        let ratios = pages.map { CGFloat($0.image.width) / CGFloat($0.image.height) }.sorted()
        let median = ratios[ratios.count / 2]
        let threshold = max(0.9, median * doubleRatioFactor)
        for i in pages.indices where CGFloat(pages[i].image.width) / CGFloat(pages[i].image.height) > threshold {
            pages[i].isDouble = true
        }

        // Some rips ship the spread *and* its two halves — then the spread is redundant.
        var split = 0, dropped = 0
        for i in pages.indices where pages[i].isDouble {
            if alreadySplit(pages, i) { pages[i].drop = true; dropped += 1 } else { split += 1 }
        }
        if split > 0 { log("\(split) tavole doppie da dividere") }
        if dropped > 0 { log("\(dropped) tavole doppie ridondanti rimosse") }

        // Build the final page list.
        var out: [Entry] = []
        for page in pages where !page.drop {
            if page.isDouble {
                let first = half(page.image, left: !manga)   // manga reads right-to-left
                let second = half(page.image, left: manga)
                for img in [first, second].compactMap({ $0 }) {
                    guard let data = encodeJPEG(fit(img, maxW: maxW, maxH: maxH), quality: jpegQuality)
                    else { continue }
                    out.append(Entry(name: name(out.count + 1, "jpg"), data: data))
                }
            } else {
                let scaled = fit(page.image, maxW: maxW, maxH: maxH)
                if scaled.width != page.image.width, let data = encodeJPEG(scaled, quality: jpegQuality) {
                    out.append(Entry(name: name(out.count + 1, "jpg"), data: data))
                } else {
                    out.append(Entry(name: name(out.count + 1, page.ext), data: page.data))
                }
            }
        }
        log("\(out.count) pagine finali")

        // Stage on disk: ImageOptim works on files, and the zip is written from there.
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ComicOptimizer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        for e in out { try e.data.write(to: temp.appendingPathComponent(e.name)) }

        if useImageOptim && ImageOptim.available {
            log("ImageOptim…")
            try ImageOptim.run(files: out.map { temp.appendingPathComponent($0.name) })
        }

        let final = try out.map {
            Entry(name: $0.name, data: try Data(contentsOf: temp.appendingPathComponent($0.name)))
        }
        let output = outputURL(for: input)
        try writeCBZ(final, to: output)
        log("→ \(output.lastPathComponent) (\(size(final.reduce(0) { $0 + $1.data.count })))")
        return output
    }

    // MARK: -

    private static func name(_ n: Int, _ ext: String) -> String {
        String(format: "%03d.%@", n, ext.isEmpty ? "jpg" : ext)
    }

    private static func load(_ input: URL) throws -> [Entry] {
        guard (try? input.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            return try readArchive(input).filter { isImageName($0.name) }
        }
        let files = FileManager.default.enumerator(at: input, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { isImageName($0.lastPathComponent) } ?? []
        return try files.map { Entry(name: $0.lastPathComponent, data: try Data(contentsOf: $0)) }
    }

    /// True if the two pages before or after the spread are the spread's own halves.
    private static func alreadySplit(_ pages: [Page], _ i: Int) -> Bool {
        guard let l = half(pages[i].image, left: true), let r = half(pages[i].image, left: false)
        else { return false }
        let lh = dhash(l), rh = dhash(r)
        for j in [i - 2, i + 1] {
            guard j >= 0, j + 1 < pages.count, j != i, j + 1 != i else { continue }
            let a = pages[j].hash, b = pages[j + 1].hash
            guard !pages[j].isDouble, !pages[j + 1].isDouble else { continue }
            let forward = hamming(a, lh) <= hashThreshold && hamming(b, rh) <= hashThreshold
            let reverse = hamming(a, rh) <= hashThreshold && hamming(b, lh) <= hashThreshold
            if forward || reverse { return true }
        }
        return false
    }

    static func outputURL(for input: URL) -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let plain = dir.appendingPathComponent(base + ".cbz")
        if plain != input && !FileManager.default.fileExists(atPath: plain.path) { return plain }
        return dir.appendingPathComponent(base + " (ottimizzato).cbz")
    }

    private static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
