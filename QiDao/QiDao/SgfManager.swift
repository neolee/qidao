import Foundation
import qidao_coreFFI

class SgfManager {
    func loadSgf(url: URL) throws -> Game {
        let data = try Data(contentsOf: url)
        var content: String?

        // Try UTF-8 first
        content = String(data: data, encoding: .utf8)

        // If failed, try GB18030 (common for Chinese SGFs)
        if content == nil {
            let gbkEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            content = String(data: data, encoding: String.Encoding(rawValue: gbkEncoding))
        }

        // Fallback to ASCII if all else fails
        if content == nil {
            content = String(data: data, encoding: .ascii)
        }

        guard let sgfContent = content else {
            throw NSError(domain: "SgfManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode SGF file".localized])
        }

        return try Game.fromSgf(sgfContent: sgfContent)
    }

    func saveSgf(game: Game, url: URL) throws {
        let content = game.toSgf()
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
