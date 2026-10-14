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

/// Everything the editor needs: the whole book to page through, which page is under
/// review, and the cuts the pipeline would have made by itself.
struct ReviewContext {
    let pages: [CGImage]
    let index: Int
    let suggestedCuts: [CGFloat]
}

/// What to do with a page the pipeline won't ship untouched.
enum PageDecision {
    case keep
    case drop
    case replace([CGImage])   // pieces in left-to-right order
}

private struct Page {
    enum Kind { case normal, double, odd }

    var image: CGImage
    var data: Data
    var ext: String
    var hash: UInt64
    var kind: Kind = .normal
    var drop = false
}

enum Pipeline {
    static let maxW = 2048, maxH = 2732      // iPad Pro 12.9" native resolution
    static let jpegQuality: CGFloat = 0.81   // same as the ImageOptim JPEG slider
    static let hashThreshold = 12            // out of 64 bits
    static let normalTolerance: CGFloat = 0.25
    static let doubleTolerance: CGFloat = 0.30

    static func run(input: URL,
                    manga: Bool,
                    useImageOptim: Bool,
                    log: (String) -> Void,
                    preflight: ([CGImage]) async -> Set<Int>?,
                    review: (ReviewContext) async -> PageDecision) async throws -> URL {
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

        // Let the reader bin the junk pages before anything is measured or cut.
        guard let discarded = await preflight(pages.map(\.image)) else { throw ArchiveError.cancelled }
        if !discarded.isEmpty {
            pages.remove(atOffsets: IndexSet(discarded))
            log("\(discarded.count) pagine eliminate a mano")
            guard !pages.isEmpty else { throw ArchiveError.noImages }
        }

        // Classify against the book's own norm: ~1× is a page, ~2× is a spread,
        // anything else (foldouts, crooked scans, banners) needs a human.
        let ratios = pages.map { CGFloat($0.image.width) / CGFloat($0.image.height) }.sorted()
        let mid = ratios.count / 2
        // The norm is whatever most pages are, portrait or landscape: a book in a single
        // format, even an all-landscape one, has nothing to cut.
        let median = ratios.count % 2 == 1 ? ratios[mid] : (ratios[mid - 1] + ratios[mid]) / 2
        for i in pages.indices {
            let k = CGFloat(pages[i].image.width) / CGFloat(pages[i].image.height) / median
            pages[i].kind = abs(k - 1) <= normalTolerance ? .normal
                          : abs(k - 2) <= doubleTolerance ? .double
                          : .odd
        }

        // Some rips ship the spread *and* its two halves — then the spread is redundant.
        var dropped = 0
        for i in pages.indices where pages[i].kind == .double {
            if alreadySplit(pages, i) { pages[i].drop = true; dropped += 1 }
        }
        if dropped > 0 { log("\(dropped) tavole doppie ridondanti rimosse") }
        let toReview = pages.filter { !$0.drop && $0.kind != .normal }.count
        if toReview > 0 { log("\(toReview) pagine da rivedere: attendo la tua scelta") }

        var out: [Entry] = []
        func emit(_ image: CGImage) {
            guard let data = encodeJPEG(fit(image, maxW: maxW, maxH: maxH), quality: jpegQuality) else { return }
            out.append(Entry(name: name(out.count + 1, "jpg"), data: data))
        }

        let book = pages.map(\.image)
        for (i, page) in pages.enumerated() where !page.drop {
            guard page.kind != .normal else { passThrough(page, into: &out); continue }
            // A spread arrives with the cut already down the middle; a foldout starts bare.
            let context = ReviewContext(pages: book, index: i,
                                        suggestedCuts: page.kind == .double ? [0.5] : [])
            switch await review(context) {
            case .drop:
                continue
            case .keep:
                passThrough(page, into: &out)
            case .replace(let pieces):
                (manga ? pieces.reversed() : pieces).forEach(emit)
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

    /// Keeps the original bytes unless the page actually had to be resized —
    /// re-encoding an untouched JPEG would only add a generation of loss.
    private static func passThrough(_ page: Page, into out: inout [Entry]) {
        let scaled = fit(page.image, maxW: maxW, maxH: maxH)
        if scaled.width != page.image.width, let data = encodeJPEG(scaled, quality: jpegQuality) {
            out.append(Entry(name: name(out.count + 1, "jpg"), data: data))
        } else {
            out.append(Entry(name: name(out.count + 1, page.ext), data: page.data))
        }
    }

    private static func name(_ n: Int, _ ext: String) -> String {
        String(format: "%03d.%@", n, ext.isEmpty ? "jpg" : ext)
    }

    private static func load(_ input: URL) throws -> [Entry] {
        if input.pathExtension.lowercased() == "pdf" {
            return try readPDF(input, height: maxH, quality: jpegQuality)
        }
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
            guard pages[j].kind == .normal, pages[j + 1].kind == .normal else { continue }
            let a = pages[j].hash, b = pages[j + 1].hash
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
