import CZLib
import Foundation

public enum ZipError: Error {
    case invalid
    case inflate
    case deflate
}

public struct ZipEntry {
    public var name: String
    public var data: Data
}

public enum ZipArchive {
    public static func read(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        guard let eocd = findEOCD(bytes) else { throw ZipError.invalid }
        let count = Int(u16(bytes, eocd + 10))
        let centralSize = Int(u32(bytes, eocd + 12))
        let centralOffset = Int(u32(bytes, eocd + 16))
        guard centralOffset >= 0, centralOffset + centralSize <= bytes.count else { throw ZipError.invalid }
        var result: [String: Data] = [:]
        var cursor = centralOffset
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count else { throw ZipError.invalid }
            guard u32(bytes, cursor) == 0x02014b50 else { throw ZipError.invalid }
            let method = u16(bytes, cursor + 10)
            let compSize = Int(u32(bytes, cursor + 20))
            let uncompSize = Int(u32(bytes, cursor + 24))
            let nameLen = Int(u16(bytes, cursor + 28))
            let extraLen = Int(u16(bytes, cursor + 30))
            let commentLen = Int(u16(bytes, cursor + 32))
            let localOffset = Int(u32(bytes, cursor + 42))
            let nameStart = cursor + 46
            guard nameStart + nameLen <= bytes.count else { throw ZipError.invalid }
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLen)], as: UTF8.self)
            cursor = nameStart + nameLen + extraLen + commentLen
            if name.hasSuffix("/") { continue }
            let payload = try readLocal(bytes, offset: localOffset, method: method, compSize: compSize, uncompSize: uncompSize)
            result[name] = payload
        }
        return result
    }

    public static func write(_ files: [String: Data]) throws -> Data {
        let names = files.keys.sorted()
        var local = Data()
        var central = Data()
        for name in names {
            let fileData = files[name] ?? Data()
            let nameData = Data(name.utf8)
            let crc = fileData.withUnsafeBytes { raw -> UInt32 in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return UInt32(bitPattern: Int32(cz_crc32(base, Int32(fileData.count))))
            }
            let stored = fileData.count < 64
            var method: UInt16 = 0
            var payload = fileData
            if !stored && !fileData.isEmpty {
                var outPtr: UnsafeMutablePointer<UInt8>?
                var outLen: Int32 = 0
                let rc: Int32 = fileData.withUnsafeBytes { raw in
                    guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                    return cz_deflate_raw(base, Int32(fileData.count), &outPtr, &outLen)
                }
                if rc == 0, let outPtr {
                    payload = Data(bytes: outPtr, count: Int(outLen))
                    free(outPtr)
                    method = 8
                }
            }
            let offset = UInt32(local.count)
            local.append(u32: 0x04034b50)
            local.append(u16: 20)
            local.append(u16: 0)
            local.append(u16: method)
            local.append(u16: 0)
            local.append(u16: 0)
            local.append(u32: crc)
            local.append(u32: UInt32(payload.count))
            local.append(u32: UInt32(fileData.count))
            local.append(u16: UInt16(nameData.count))
            local.append(u16: 0)
            local.append(nameData)
            local.append(payload)

            central.append(u32: 0x02014b50)
            central.append(u16: 20)
            central.append(u16: 20)
            central.append(u16: 0)
            central.append(u16: method)
            central.append(u16: 0)
            central.append(u16: 0)
            central.append(u32: crc)
            central.append(u32: UInt32(payload.count))
            central.append(u32: UInt32(fileData.count))
            central.append(u16: UInt16(nameData.count))
            central.append(u16: 0)
            central.append(u16: 0)
            central.append(u16: 0)
            central.append(u16: 0)
            central.append(u32: 0)
            central.append(u32: offset)
            central.append(nameData)
        }
        var out = local
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(u32: 0x06054b50)
        out.append(u16: 0)
        out.append(u16: 0)
        out.append(u16: UInt16(names.count))
        out.append(u16: UInt16(names.count))
        out.append(u32: UInt32(central.count))
        out.append(u32: centralOffset)
        out.append(u16: 0)
        return out
    }

    private static func readLocal(_ bytes: [UInt8], offset: Int, method: UInt16, compSize: Int, uncompSize: Int) throws -> Data {
        guard offset + 30 <= bytes.count, u32(bytes, offset) == 0x04034b50 else { throw ZipError.invalid }
        let nameLen = Int(u16(bytes, offset + 26))
        let extraLen = Int(u16(bytes, offset + 28))
        let dataStart = offset + 30 + nameLen + extraLen
        guard dataStart + compSize <= bytes.count else { throw ZipError.invalid }
        let slice = bytes[dataStart..<(dataStart + compSize)]
        if method == 0 {
            return Data(slice)
        }
        if method == 8 {
            let destCount = max(uncompSize, 1)
            var dest = [UInt8](repeating: 0, count: destCount)
            let produced = slice.withUnsafeBufferPointer { src in
                dest.withUnsafeMutableBufferPointer { dst in
                    cz_inflate_raw(src.baseAddress, Int32(compSize), dst.baseAddress, Int32(destCount))
                }
            }
            guard produced >= 0 else { throw ZipError.inflate }
            return Data(dest.prefix(Int(produced)))
        }
        throw ZipError.invalid
    }

    private static func findEOCD(_ bytes: [UInt8]) -> Int? {
        let minStart = max(0, bytes.count - 22 - 65535)
        var index = bytes.count - 22
        while index >= minStart {
            if u32(bytes, index) == 0x06054b50 { return index }
            index -= 1
        }
        return nil
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

private extension Data {
    mutating func append(u16: UInt16) {
        append(UInt8(u16 & 0xff))
        append(UInt8((u16 >> 8) & 0xff))
    }

    mutating func append(u32: UInt32) {
        append(UInt8(u32 & 0xff))
        append(UInt8((u32 >> 8) & 0xff))
        append(UInt8((u32 >> 16) & 0xff))
        append(UInt8((u32 >> 24) & 0xff))
    }
}
