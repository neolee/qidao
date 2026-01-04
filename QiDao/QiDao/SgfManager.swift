import Foundation
import qidao_coreFFI

enum SgfManagerError: LocalizedError {
    case decodeFailed
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .decodeFailed:
            return "Failed to decode SGF file".localized
        case .parseFailed(let reason):
            return "\("Failed to parse SGF".localized): \(reason)"
        }
    }
}

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
            throw SgfManagerError.decodeFailed
        }

        do {
            return try Game.fromSgf(sgfContent: sgfContent)
        } catch {
            throw SgfManagerError.parseFailed(error.localizedDescription)
        }
    }

    func saveSgf(game: Game, url: URL) throws {
        let content = game.toSgf()
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
