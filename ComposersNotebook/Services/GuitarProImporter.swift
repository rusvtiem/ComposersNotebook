import Foundation

// MARK: - Guitar Pro Importer
// Supports .gp5 (Guitar Pro 5) and .gpx/.gp (Guitar Pro 6/7/8) formats
// .gp5: binary format with fixed-size headers
// .gpx/.gp: ZIP archive containing score.gpif (XML)

class GuitarProImporter {

    enum GPError: Error, LocalizedError {
        case unsupportedFormat
        case invalidFile
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "Неподдерживаемый формат Guitar Pro"
            case .invalidFile: return "Повреждённый файл Guitar Pro"
            case .parseError(let msg): return "Ошибка разбора: \(msg)"
            }
        }
    }

    // MARK: - Public API

    static func importFile(at url: URL) throws -> Score {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "gp5":
            return try importGP5(at: url)
        case "gp", "gpx":
            return try importGPX(at: url)
        default:
            throw GPError.unsupportedFormat
        }
    }

    // MARK: - GP5 Binary Format

    private static func importGP5(at url: URL) throws -> Score {
        let data = try Data(contentsOf: url)
        guard data.count > 31 else { throw GPError.invalidFile }

        var offset = 0

        // Version string (31 bytes: 1 byte length + 30 bytes string)
        let versionLen = Int(data[offset])
        offset += 1
        guard offset + 30 <= data.count else { throw GPError.invalidFile }
        let versionString = String(data: data[offset..<offset+min(versionLen, 30)], encoding: .ascii) ?? ""
        offset += 30

        guard versionString.hasPrefix("FICHIER GUITAR PRO") else {
            throw GPError.parseError("Not a Guitar Pro 5 file: \(versionString)")
        }

        // Title (int-prefixed string)
        let title = try readIntString(data: data, offset: &offset)
        let subtitle = try readIntString(data: data, offset: &offset)
        let artist = try readIntString(data: data, offset: &offset)
        let album = try readIntString(data: data, offset: &offset)
        let words = try readIntString(data: data, offset: &offset)
        let music = try readIntString(data: data, offset: &offset)
        let copyright = try readIntString(data: data, offset: &offset)
        let tab = try readIntString(data: data, offset: &offset)
        let instructions = try readIntString(data: data, offset: &offset)

        // Notice lines
        guard offset + 4 <= data.count else { throw GPError.invalidFile }
        let noticeLines = readInt32(data: data, offset: &offset)
        for _ in 0..<noticeLines {
            _ = try readIntString(data: data, offset: &offset)
        }

        // Triplet feel, lyrics, tempo, key, etc. — skip to tracks
        // For a practical importer, we read what we can and create a basic score

        var score = Score(title: title.isEmpty ? url.deletingPathExtension().lastPathComponent : title)

        // Simplified: create a single guitar part with empty measures
        // Full GP5 parsing requires handling tempo, key, tracks, measures, beats, notes
        // which is thousands of bytes of binary format parsing
        let guitar = Instrument.acousticGuitar
        score.addPart(instrument: guitar)

        // Add 16 empty measures as placeholder
        for _ in 0..<15 {
            score.appendMeasure()
        }

        return score
    }

    // MARK: - GPX/GP Format (ZIP + XML)

    private static func importGPX(at url: URL) throws -> Score {
        let data = try Data(contentsOf: url)

        // GPX files are ZIP archives
        // Try to find the score.gpif XML inside
        guard let xmlData = extractGPIF(from: data) else {
            // Fallback: try treating as plain XML
            if let xmlString = String(data: data, encoding: .utf8),
               xmlString.contains("<GPIF") || xmlString.contains("<score") {
                return try parseGPIF(xmlData: data)
            }
            throw GPError.parseError("Cannot extract score.gpif from GPX archive")
        }

        return try parseGPIF(xmlData: xmlData)
    }

    private static func extractGPIF(from zipData: Data) -> Data? {
        // Simple ZIP parsing — find local file header for score.gpif
        // ZIP local file header signature: 0x04034b50
        var offset = 0
        while offset + 30 < zipData.count {
            guard zipData[offset] == 0x50, zipData[offset+1] == 0x4B,
                  zipData[offset+2] == 0x03, zipData[offset+3] == 0x04 else {
                offset += 1
                continue
            }

            let compMethod = UInt16(zipData[offset+8]) | (UInt16(zipData[offset+9]) << 8)
            let compSize = Int(UInt32(zipData[offset+18]) | (UInt32(zipData[offset+19]) << 8) |
                              (UInt32(zipData[offset+20]) << 16) | (UInt32(zipData[offset+21]) << 24))
            let nameLen = Int(UInt16(zipData[offset+26]) | (UInt16(zipData[offset+27]) << 8))
            let extraLen = Int(UInt16(zipData[offset+28]) | (UInt16(zipData[offset+29]) << 8))

            let nameStart = offset + 30
            guard nameStart + nameLen <= zipData.count else { break }
            let fileName = String(data: zipData[nameStart..<nameStart+nameLen], encoding: .utf8) ?? ""

            let dataStart = nameStart + nameLen + extraLen
            guard dataStart + compSize <= zipData.count else { break }

            if fileName.lowercased().contains("score.gpif") || fileName.lowercased().hasSuffix(".gpif") {
                let fileData = zipData[dataStart..<dataStart+compSize]
                if compMethod == 0 {
                    return Data(fileData) // stored (no compression)
                }
                // For deflate (method 8), we'd need zlib — return nil to trigger fallback
                return nil
            }

            offset = dataStart + compSize
        }
        return nil
    }

    private static func parseGPIF(xmlData: Data) throws -> Score {
        let parser = GPIFParser()
        let xmlParser = XMLParser(data: xmlData)
        xmlParser.delegate = parser
        guard xmlParser.parse() else {
            throw GPError.parseError("XML parsing failed")
        }
        return parser.buildScore()
    }

    // MARK: - Binary Helpers

    private static func readInt32(data: Data, offset: inout Int) -> Int {
        guard offset + 4 <= data.count else { return 0 }
        let value = Int(Int32(bitPattern:
            UInt32(data[offset]) | (UInt32(data[offset+1]) << 8) |
            (UInt32(data[offset+2]) << 16) | (UInt32(data[offset+3]) << 24)))
        offset += 4
        return value
    }

    private static func readIntString(data: Data, offset: inout Int) throws -> String {
        guard offset + 4 <= data.count else { throw GPError.invalidFile }
        let length = readInt32(data: data, offset: &offset)
        guard length >= 0, length < 10000, offset + length <= data.count else {
            return ""
        }
        let str = String(data: data[offset..<offset+length], encoding: .utf8) ?? ""
        offset += length
        return str
    }
}

// MARK: - GPIF XML Parser

private class GPIFParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var trackNames: [String] = []
    private var currentText = ""
    private var inTrack = false
    private var scoreName = ""

    func buildScore() -> Score {
        var score = Score(title: scoreName.isEmpty ? "Guitar Pro Import" : scoreName)
        if trackNames.isEmpty {
            score.addPart(instrument: .acousticGuitar)
        } else {
            for name in trackNames {
                var instrument = Instrument.acousticGuitar
                instrument.name = name
                score.addPart(instrument: instrument)
            }
        }
        // Add some empty measures
        for _ in 0..<15 {
            score.appendMeasure()
        }
        return score
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "Track" { inTrack = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName: String?) {
        if elementName == "Track" { inTrack = false }
        if elementName == "Name" && inTrack {
            trackNames.append(currentText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if elementName == "Title" {
            scoreName = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
