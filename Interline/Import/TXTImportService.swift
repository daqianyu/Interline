import Foundation
import CoreFoundation
import CryptoKit

public enum TextEncodingChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic = "自动识别"
    case utf8 = "UTF-8"
    case utf16LE = "UTF-16 LE"
    case utf16BE = "UTF-16 BE"
    case gb18030 = "GB18030 / GBK"
    public var id: String { rawValue }

    var encoding: String.Encoding? {
        switch self {
        case .automatic: return nil
        case .utf8: return .utf8
        case .utf16LE: return .utf16LittleEndian
        case .utf16BE: return .utf16BigEndian
        // kCFStringEncodingGB_18030_2000; includes the GBK/GB2312 repertoire.
        case .gb18030: return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0632))
        }
    }
}

public enum TextImportError: LocalizedError {
    case tooLarge, unsupported, empty, decoding
    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "文件超过 20 MB，请先拆分后再导入"
        case .unsupported: return "目前支持 TXT 纯文本文件"
        case .empty: return "文件没有可阅读的正文"
        case .decoding: return "无法正确解码，请在编码选项中手动选择"
        }
    }
}

public struct ImportSource: Identifiable, Sendable {
    public let id = UUID()
    public let data: Data
    public let fileName: String
}

public struct ParsedTextBook: Sendable {
    public var book: Book
    public let detectedEncoding: String
}

public enum TXTImportService {
    public static let maximumBytes = 20 * 1_024 * 1_024

    /// Called off the main actor. Copy into memory while security-scoped access is held.
    public static func read(url: URL) throws -> ImportSource {
        guard url.pathExtension.lowercased() == "txt" else { throw TextImportError.unsupported }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var result: Result<Data, Error>?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result {
                let bytes = try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard bytes <= maximumBytes else { throw TextImportError.tooLarge }
                let data = try Data(contentsOf: coordinated)
                guard data.count <= maximumBytes else { throw TextImportError.tooLarge }
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw TextImportError.decoding }
        return ImportSource(data: try result.get(), fileName: url.lastPathComponent)
    }

    public static func parse(data: Data, fileName: String, encoding choice: TextEncodingChoice = .automatic) throws -> ParsedTextBook {
        guard data.count <= maximumBytes else { throw TextImportError.tooLarge }
        try Task.checkCancellation()
        let (decoded, detected) = try decode(data, choice: choice)
        let normalized = decoded.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TextImportError.empty }
        guard !normalized.unicodeScalars.contains(where: { $0.value == 0 || ($0.value < 32 && ![9, 10].contains($0.value)) }) else {
            throw TextImportError.decoding
        }
        // Content identity is independent of the original file name and line endings.
        let fingerprint = SHA256.hash(data: Data(normalized.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
            .map { String(format: "%02x", $0) }.joined()
        let bookID = "txt-" + fingerprint
        let heading = try NSRegularExpression(pattern:
            #"^(?:第[零〇一二三四五六七八九十百千万两0-9]+[章节回卷部篇集].{0,50}|[Cc][Hh][Aa][Pp][Tt][Ee][Rr]\s+[0-9]+.{0,50}|序章|序言|前言|楔子|尾声|后记)$"#)
        var chapters: [Chapter] = []
        var title = "正文"
        var paragraphs: [String] = []
        var count = 0
        var part = 1
        func flush() {
            guard !paragraphs.isEmpty || title != "正文" else { return }
            chapters.append(Chapter(id: "\(bookID)-\(chapters.count)", title: title, content: paragraphs))
            paragraphs = []
            count = 0
        }
        for (index, rawLine) in normalized.components(separatedBy: .newlines).enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.utf16.count <= 80 && heading.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) != nil {
                flush()
                title = line
                part = 1
            } else {
                // Bound individual paragraphs and chapter layout work for unstructured TXT.
                var start = line.startIndex
                while start < line.endIndex {
                    let end = line.index(start, offsetBy: 4_000, limitedBy: line.endIndex) ?? line.endIndex
                    let piece = String(line[start..<end])
                    if count + piece.utf16.count > 32_000 && !paragraphs.isEmpty {
                        let original = title.components(separatedBy: " · 分段 ").first ?? title
                        flush()
                        part += 1
                        title = "\(original) · 分段 \(part)"
                    }
                    paragraphs.append(piece)
                    count += piece.utf16.count
                    start = end
                }
            }
        }
        flush()
        guard !chapters.isEmpty else { throw TextImportError.empty }
        var book = Book(id: bookID, title: (fileName as NSString).deletingPathExtension, author: "未知作者", chapters: chapters)
        book.contentFingerprint = fingerprint
        book.sourceEncoding = detected
        return ParsedTextBook(book: book, detectedEncoding: detected)
    }

    private static func decode(_ data: Data, choice: TextEncodingChoice) throws -> (String, String) {
        if let encoding = choice.encoding {
            guard let text = String(data: data, encoding: encoding) else { throw TextImportError.decoding }
            return (text, choice.rawValue)
        }
        if data.starts(with: [0xFF, 0xFE]), let text = String(data: data, encoding: .utf16LittleEndian) { return (text, "UTF-16 LE") }
        if data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16BigEndian) { return (text, "UTF-16 BE") }
        if let text = String(data: data, encoding: .utf8), !text.contains("\0") { return (text, "UTF-8") }
        // NUL placement is a useful hint for UTF-16 files without a BOM.
        let prefix = Array(data.prefix(512))
        if prefix.contains(0) {
            let evenZeros = prefix.enumerated().filter { $0.offset.isMultiple(of: 2) && $0.element == 0 }.count
            let oddZeros = prefix.enumerated().filter { !$0.offset.isMultiple(of: 2) && $0.element == 0 }.count
            let choices: [TextEncodingChoice] = evenZeros > oddZeros ? [.utf16BE, .utf16LE] : [.utf16LE, .utf16BE]
            for encoding in choices {
                if let text = String(data: data, encoding: encoding.encoding!), !text.contains("\0") { return (text, encoding.rawValue) }
            }
        }
        if let text = String(data: data, encoding: TextEncodingChoice.gb18030.encoding!) { return (text, TextEncodingChoice.gb18030.rawValue) }
        throw TextImportError.decoding
    }
}
