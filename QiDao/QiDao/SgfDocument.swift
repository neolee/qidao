import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var sgf: UTType {
        UTType("net.paradigmx.qidao.sgf") ?? UTType(filenameExtension: "sgf") ?? .data
    }
}

struct SgfDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.sgf] }

    var sgfContent: String

    init(sgfContent: String = "") {
        self.sgfContent = sgfContent
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        sgfContent = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = sgfContent.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
}
