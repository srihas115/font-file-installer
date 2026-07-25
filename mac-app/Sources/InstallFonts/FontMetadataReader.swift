import CoreGraphics
import CoreText
import Foundation

struct FontFileMetadata {
    let familyName: String?
    let styleName: String?
    let designer: String?
    let license: String?
}

enum FontMetadataReader {
    static func metadata(for url: URL) -> FontFileMetadata {
        guard let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider) else {
            return FontFileMetadata(familyName: nil, styleName: nil, designer: nil, license: nil)
        }

        let coreTextFont = CTFontCreateWithGraphicsFont(font, 0, nil, nil)
        guard let tableData = CTFontCopyTable(coreTextFont, CTFontTableTag(kCTFontTableName), []) as Data? else {
            return FontFileMetadata(familyName: nil, styleName: nil, designer: nil, license: nil)
        }

        let nameTable = OpenTypeNameTable(data: tableData)
        return FontFileMetadata(
            familyName: nameTable.bestString(for: [16, 1]) ?? clean(font.fullName as String?),
            styleName: nameTable.bestString(for: [17, 2]),
            designer: nameTable.bestString(for: [9, 8]),
            license: nameTable.bestString(for: [13, 14])
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else {
            return nil
        }
        return cleaned
    }
}

private struct OpenTypeNameTable {
    struct NameRecord {
        let platformID: UInt16
        let encodingID: UInt16
        let languageID: UInt16
        let nameID: UInt16
        let length: UInt16
        let offset: UInt16
    }

    let data: Data
    let records: [NameRecord]
    let stringOffset: Int

    init(data: Data) {
        self.data = data
        let count = Int(Self.readUInt16(data, at: 2) ?? 0)
        self.stringOffset = Int(Self.readUInt16(data, at: 4) ?? 0)

        var parsedRecords: [NameRecord] = []
        parsedRecords.reserveCapacity(count)

        for index in 0..<count {
            let start = 6 + (index * 12)
            guard start + 12 <= data.count,
                  let platformID = Self.readUInt16(data, at: start),
                  let encodingID = Self.readUInt16(data, at: start + 2),
                  let languageID = Self.readUInt16(data, at: start + 4),
                  let nameID = Self.readUInt16(data, at: start + 6),
                  let length = Self.readUInt16(data, at: start + 8),
                  let offset = Self.readUInt16(data, at: start + 10) else {
                continue
            }

            parsedRecords.append(NameRecord(
                platformID: platformID,
                encodingID: encodingID,
                languageID: languageID,
                nameID: nameID,
                length: length,
                offset: offset
            ))
        }

        self.records = parsedRecords
    }

    func bestString(for nameIDs: [UInt16]) -> String? {
        for nameID in nameIDs {
            let candidates = records
                .filter { $0.nameID == nameID }
                .compactMap { record -> (value: String, score: Int)? in
                    guard let value = string(for: record) else { return nil }
                    return (value, score(record))
                }
                .sorted { $0.score > $1.score }

            if let best = candidates.first?.value {
                return best
            }
        }

        return nil
    }

    private func string(for record: NameRecord) -> String? {
        let start = stringOffset + Int(record.offset)
        let end = start + Int(record.length)
        guard start >= 0, end <= data.count, start < end else { return nil }

        let stringData = data.subdata(in: start..<end)
        let decoded: String?

        if record.platformID == 0 || record.platformID == 3 {
            decoded = String(data: stringData, encoding: .utf16BigEndian)
        } else if record.platformID == 1 {
            decoded = String(data: stringData, encoding: .macOSRoman)
                ?? String(data: stringData, encoding: .utf8)
        } else {
            decoded = String(data: stringData, encoding: .utf8)
                ?? String(data: stringData, encoding: .utf16BigEndian)
        }

        guard let cleaned = decoded?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else {
            return nil
        }

        return cleaned
    }

    private func score(_ record: NameRecord) -> Int {
        var value = 0

        if record.platformID == 3 { value += 40 }
        if record.platformID == 0 { value += 30 }
        if record.platformID == 1 { value += 10 }
        if record.languageID == 0x0409 { value += 20 }
        if record.languageID == 0 { value += 15 }
        if record.encodingID == 1 || record.encodingID == 10 { value += 5 }

        return value
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }
}
