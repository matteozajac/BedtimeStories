import Foundation

/// Bedtime Story v1: single-disk ZIP32, stored entries, no descriptors or encryption.
public enum StoryArchive {
    public static let maximumBytes: UInt64 = 2 * 1_024 * 1_024 * 1_024
    public static let maximumEntries = 10_000
    private static let chunkSize = 256 * 1_024

    private struct Entry {
        let name: String
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
        let flags: UInt16
    }

    public static func extract(_ archive: URL, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw BookError.invalid("Import staging folder already exists.") }
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        let fileSize = try input.seekToEnd()
        guard fileSize >= 22, fileSize <= maximumBytes + 16_000_000 else { throw BookError.invalid("Archive is empty or too large.") }
        let tailSize = min(fileSize, 65_557)
        try input.seek(toOffset: fileSize - tailSize)
        let tail = try read(input, Int(tailSize))
        var end: Int?
        for index in stride(from: tail.count - 22, through: 0, by: -1) {
            if tail.u32(index) == 0x06054b50, index + 22 + Int(tail.u16(index + 20)) == tail.count { end = index; break }
        }
        guard let end, tail.u16(end + 4) == 0, tail.u16(end + 6) == 0,
              tail.u16(end + 8) == tail.u16(end + 10) else { throw BookError.invalid("Unsupported or incomplete ZIP archive.") }
        let count = Int(tail.u16(end + 10))
        let centralSize = UInt64(tail.u32(end + 12))
        let centralOffset = UInt64(tail.u32(end + 16))
        guard count > 0, count <= maximumEntries,
              centralOffset + centralSize == fileSize - tailSize + UInt64(end) else { throw BookError.invalid("Invalid ZIP directory.") }
        try input.seek(toOffset: centralOffset)
        var entries: [Entry] = []
        var names = Set<String>()
        var total: UInt64 = 0
        for _ in 0..<count {
            let header = try read(input, 46)
            guard header.u32(0) == 0x02014b50, header.u16(6) <= 20, header.u16(10) == 0,
                  header.u16(8) & ~UInt16(0x0800) == 0, header.u16(34) == 0 else {
                throw BookError.invalid("Only uncompressed, unencrypted Bedtime Story v1 archives are supported.")
            }
            let size = header.u32(24)
            guard size == header.u32(20) else { throw BookError.invalid("Invalid stored file size.") }
            let nameBytes = try read(input, Int(header.u16(28)))
            guard let rawName = String(data: nameBytes, encoding: .utf8) else { throw BookError.invalid("Archive filenames must be UTF-8.") }
            let isDirectory = rawName.hasSuffix("/")
            let name = isDirectory ? String(rawName.dropLast()) : rawName
            try SafeBookPath.validate(name)
            // Canonical equivalence and case folding prevent collisions on Apple filesystems.
            let key = name.precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(key).inserted else { throw BookError.invalid("Duplicate archive path: \(name).") }
            let unixType = (header.u32(38) >> 16) & 0xf000
            guard unixType == 0 || unixType == (isDirectory ? 0x4000 : 0x8000) else { throw BookError.invalid("Archive links and special files are not allowed.") }
            guard !isDirectory || size == 0 else { throw BookError.invalid("Invalid directory entry.") }
            let extra = try read(input, Int(header.u16(30)))
            try rejectZIP64(extra)
            _ = try read(input, Int(header.u16(32)))
            total += UInt64(size)
            guard total <= maximumBytes, try input.offset() <= centralOffset + centralSize else { throw BookError.invalid("Archive exceeds import limits.") }
            entries.append(Entry(name: rawName, crc: header.u32(16), size: size, offset: header.u32(42), flags: header.u16(8)))
        }
        guard try input.offset() == centralOffset + centralSize, entries.contains(where: { $0.name == "book.json" }) else { throw BookError.invalid("Archive needs book.json at its root.") }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            var ranges: [Range<UInt64>] = []
            for entry in entries {
                try Task.checkCancellation()
                try input.seek(toOffset: UInt64(entry.offset))
                let local = try read(input, 30)
                guard local.u32(0) == 0x04034b50, local.u16(4) <= 20, local.u16(6) == entry.flags,
                      local.u16(8) == 0, local.u32(14) == entry.crc,
                      local.u32(18) == entry.size, local.u32(22) == entry.size else { throw BookError.invalid("ZIP headers disagree.") }
                let nameData = try read(input, Int(local.u16(26)))
                guard String(data: nameData, encoding: .utf8) == entry.name else { throw BookError.invalid("ZIP filenames disagree.") }
                try rejectZIP64(read(input, Int(local.u16(28))))
                let start = try input.offset()
                let finish = start + UInt64(entry.size)
                let range = UInt64(entry.offset)..<finish
                guard finish <= centralOffset, !ranges.contains(where: { $0.overlaps(range) }) else { throw BookError.invalid("Overlapping ZIP entries.") }
                ranges.append(range)
                let directory = entry.name.hasSuffix("/")
                let url = try SafeBookPath.resolve(directory ? String(entry.name.dropLast()) : entry.name, inside: destination)
                if directory {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    continue
                }
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw BookError.unavailable("Cannot create imported file.") }
                let output = try FileHandle(forWritingTo: url)
                do {
                    var remaining = Int(entry.size)
                    var crc: UInt32 = 0xffffffff
                    while remaining > 0 {
                        try Task.checkCancellation()
                        let data = try read(input, min(chunkSize, remaining))
                        crc = updateCRC(crc, data)
                        try output.write(contentsOf: data)
                        remaining -= data.count
                    }
                    try output.close()
                    guard crc ^ 0xffffffff == entry.crc else { throw BookError.invalid("A file failed its checksum: \(entry.name).") }
                } catch { try? output.close(); throw error }
            }
            _ = try BookManifest.load(from: destination, requireAssets: true)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    public static func create(from folder: URL, at archive: URL) throws {
        let book = try BookManifest.load(from: folder, requireAssets: true)
        let paths = Array(Set(["book.json"] + book.assetPaths)).sorted()
        guard paths.count <= maximumEntries else { throw BookError.invalid("Too many files.") }
        guard !FileManager.default.fileExists(atPath: archive.path), FileManager.default.createFile(atPath: archive.path, contents: nil) else { throw BookError.unavailable("Cannot create share file.") }
        let output = try FileHandle(forWritingTo: archive)
        do {
            var entries: [Entry] = []
            var total: UInt64 = 0
            for path in paths {
                try Task.checkCancellation()
                let source = try SafeBookPath.resolve(path, inside: folder)
                let input = try FileHandle(forReadingFrom: source)
                do {
                    let length = try input.seekToEnd()
                    total += length
                    guard total <= maximumBytes, length < UInt64(UInt32.max) else { throw BookError.invalid("Book exceeds export limits.") }
                    try input.seek(toOffset: 0)
                    let offset = try output.offset()
                    let name = Data(path.utf8)
                    guard name.count <= Int(UInt16.max), offset < UInt64(UInt32.max) else { throw BookError.invalid("Filename or archive is too large.") }
                    var header = Data()
                    header.put32(0x04034b50); header.put16(20); header.put16(0x0800); header.put16(0)
                    header.put16(0); header.put16(33); header.put32(0); header.put32(UInt32(length)); header.put32(UInt32(length))
                    header.put16(UInt16(name.count)); header.put16(0)
                    try output.write(contentsOf: header); try output.write(contentsOf: name)
                    var crc: UInt32 = 0xffffffff
                    var remaining = Int(length)
                    while remaining > 0 {
                        try Task.checkCancellation()
                        let chunk = try read(input, min(chunkSize, remaining))
                        crc = updateCRC(crc, chunk); try output.write(contentsOf: chunk); remaining -= chunk.count
                    }
                    let finish = try output.offset()
                    crc ^= 0xffffffff
                    try output.seek(toOffset: offset + 14)
                    var checksum = Data(); checksum.put32(crc); try output.write(contentsOf: checksum)
                    try output.seek(toOffset: finish)
                    entries.append(Entry(name: path, crc: crc, size: UInt32(length), offset: UInt32(offset), flags: 0x0800))
                    try input.close()
                } catch { try? input.close(); throw error }
            }
            let centralOffset = try output.offset()
            for entry in entries {
                var header = Data()
                header.put32(0x02014b50); header.put16(20); header.put16(20); header.put16(entry.flags); header.put16(0)
                header.put16(0); header.put16(33); header.put32(entry.crc); header.put32(entry.size); header.put32(entry.size)
                let name = Data(entry.name.utf8)
                header.put16(UInt16(name.count)); header.put16(0); header.put16(0); header.put16(0); header.put16(0)
                header.put32(0); header.put32(entry.offset)
                try output.write(contentsOf: header); try output.write(contentsOf: name)
            }
            let centralSize = try output.offset() - centralOffset
            var end = Data()
            end.put32(0x06054b50); end.put16(0); end.put16(0); end.put16(UInt16(entries.count)); end.put16(UInt16(entries.count))
            end.put32(UInt32(centralSize)); end.put32(UInt32(centralOffset)); end.put16(0)
            try output.write(contentsOf: end); try output.close()
        } catch {
            try? output.close(); try? FileManager.default.removeItem(at: archive); throw error
        }
    }

    private static func read(_ handle: FileHandle, _ count: Int) throws -> Data {
        if count == 0 { return Data() }
        guard let data = try handle.read(upToCount: count), data.count == count else { throw BookError.invalid("Truncated archive or file.") }
        return data
    }
    private static func rejectZIP64(_ extra: Data) throws {
        var index = 0
        while index < extra.count {
            guard index + 4 <= extra.count else { throw BookError.invalid("Invalid ZIP metadata.") }
            let size = Int(extra.u16(index + 2))
            guard extra.u16(index) != 1, index + 4 + size <= extra.count else { throw BookError.invalid("ZIP64 is not supported in v1.") }
            index += 4 + size
        }
    }
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        return crc
    }
    private static func updateCRC(_ seed: UInt32, _ bytes: Data) -> UInt32 {
        var crc = seed
        for byte in bytes { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
    mutating func put16(_ value: UInt16) { append(UInt8(value & 0xff)); append(UInt8(value >> 8)) }
    mutating func put32(_ value: UInt32) { put16(UInt16(value & 0xffff)); put16(UInt16(value >> 16)) }
}
