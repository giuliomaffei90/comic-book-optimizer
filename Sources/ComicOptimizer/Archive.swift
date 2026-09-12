import Foundation
import CArchive

private let AE_IFREG: mode_t = 0o100000

enum ArchiveError: LocalizedError {
    case open(String), write(String), noImages, cancelled

    var errorDescription: String? {
        switch self {
        case .open(let m):  return "Impossibile aprire l'archivio: \(m)"
        case .write(let m): return "Impossibile scrivere il .cbz: \(m)"
        case .noImages:     return "Nessuna immagine trovata."
        case .cancelled:    return "Annullato."
        }
    }
}

struct Entry {
    var name: String
    var data: Data
}

private func err(_ a: OpaquePointer?) -> String {
    archive_error_string(a).map { String(cString: $0) } ?? "errore sconosciuto"
}

/// Reads every regular file out of a zip/cbz/cbr/rar/7z into memory.
func readArchive(_ url: URL) throws -> [Entry] {
    let a = archive_read_new()
    defer { archive_read_free(a) }
    archive_read_support_filter_all(a)
    archive_read_support_format_all(a)
    guard archive_read_open_filename(a, url.path, 1 << 16) == 0 else {
        throw ArchiveError.open(err(a))
    }

    var out: [Entry] = []
    var entry: OpaquePointer?
    var buf = [UInt8](repeating: 0, count: 1 << 18)
    while archive_read_next_header(a, &entry) == 0 {
        guard archive_entry_filetype(entry) == AE_IFREG else { continue }
        let cName = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry)
        guard let cName else { continue }
        var data = Data()
        while true {
            let n = buf.withUnsafeMutableBytes { archive_read_data(a, $0.baseAddress, $0.count) }
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
        }
        out.append(Entry(name: String(cString: cName), data: data))
    }
    return out
}

/// Writes a stored (uncompressed) zip — JPEGs don't deflate, so compression is wasted CPU.
func writeCBZ(_ entries: [Entry], to url: URL) throws {
    let a = archive_write_new()
    defer { archive_write_free(a) }
    archive_write_set_format_zip(a)
    archive_write_zip_set_compression_store(a)
    guard archive_write_open_filename(a, url.path) == 0 else {
        throw ArchiveError.write(err(a))
    }
    for e in entries {
        let entry = archive_entry_new()
        defer { archive_entry_free(entry) }
        archive_entry_set_pathname(entry, e.name)
        archive_entry_set_size(entry, Int64(e.data.count))
        archive_entry_set_filetype(entry, UInt32(AE_IFREG))
        archive_entry_set_perm(entry, 0o644)
        guard archive_write_header(a, entry) == 0 else { throw ArchiveError.write(err(a)) }
        _ = e.data.withUnsafeBytes { archive_write_data(a, $0.baseAddress, $0.count) }
    }
    guard archive_write_close(a) == 0 else { throw ArchiveError.write(err(a)) }
}
