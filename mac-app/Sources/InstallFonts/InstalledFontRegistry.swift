import Foundation

struct InstalledFontRecord: Codable, Identifiable, Hashable {
    let fileName: String
    var source: String
    var installedAt: Date

    var id: String { fileName }
}

enum InstalledFontRegistry {
    private static let recordsKey = "installedFontRecords"

    static func records() -> [String: InstalledFontRecord] {
        guard let data = UserDefaults.standard.data(forKey: recordsKey),
              let decoded = try? JSONDecoder().decode([String: InstalledFontRecord].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func record(_ result: InstallResult, source: String) {
        guard !result.installed.isEmpty else { return }

        var existing = records()
        let now = Date()
        for fileName in result.installed {
            existing[fileName] = InstalledFontRecord(fileName: fileName, source: source, installedAt: now)
        }
        save(existing)
    }

    static func remove(fileNames: Set<String>) {
        var existing = records()
        for fileName in fileNames {
            existing.removeValue(forKey: fileName)
        }
        save(existing)
    }

    private static func save(_ records: [String: InstalledFontRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }
}
