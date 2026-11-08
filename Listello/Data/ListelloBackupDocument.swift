import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let listelloBackup = UTType(exportedAs: "com.krabople.listello.backup", conformingTo: .json)
}

struct ListelloBackup: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let exportedAt: Date
    let state: ListelloState

    init(state: ListelloState, exportedAt: Date = Date()) {
        formatVersion = Self.currentFormatVersion
        self.exportedAt = exportedAt
        self.state = state
    }

    init(from data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
        guard formatVersion <= Self.currentFormatVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct ListelloBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.listelloBackup, .json] }

    let backup: ListelloBackup

    init(backup: ListelloBackup) {
        self.backup = backup
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        backup = try ListelloBackup(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try backup.encoded())
    }
}
