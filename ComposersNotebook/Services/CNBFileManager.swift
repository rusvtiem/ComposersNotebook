import Foundation
import UniformTypeIdentifiers

// MARK: - CNB File Format
// .cnb = zip container with versioned JSON structure
// Similar to .mscz (MuseScore) or .pages (Apple)

/// Supported CNB format versions
enum CNBFormatVersion: Int, Codable {
    case v1 = 1

    static let current: CNBFormatVersion = .v1
}

/// Metadata stored inside .cnb container
struct CNBMetadata: Codable {
    let formatVersion: Int
    let appVersion: String
    let createdAt: Date
    let modifiedAt: Date
    let title: String
    let composer: String

    static func current(score: Score) -> CNBMetadata {
        CNBMetadata(
            formatVersion: CNBFormatVersion.current.rawValue,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            createdAt: score.createdAt,
            modifiedAt: Date(),
            title: score.title,
            composer: score.composer
        )
    }
}

/// CNB file container structure
struct CNBContainer: Codable {
    let metadata: CNBMetadata
    let score: Score
    let settings: CNBSettings?
}

/// Per-file settings (sound presets, view preferences)
struct CNBSettings: Codable {
    var soundPresets: [String: SoundPreset]?
    var zoomScale: Double?
    var selectedPartIndex: Int?

    struct SoundPreset: Codable {
        var volume: Float
        var pan: Float
        var reverb: Float
        var presetName: String?
    }
}

// MARK: - UTType Extension
extension UTType {
    static let cnb = UTType(exportedAs: "com.timshega.composersnotebook.cnb")
}

// MARK: - CNBFileManager
class CNBFileManager {

    static let shared = CNBFileManager()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    // MARK: - Save

    /// Save score to .cnb file (zip container with JSON)
    func save(score: Score, settings: CNBSettings? = nil, to url: URL) throws {
        let metadata = CNBMetadata.current(score: score)
        let container = CNBContainer(metadata: metadata, score: score, settings: settings)

        // Encode to JSON
        let jsonData = try encoder.encode(container)

        // Compress with zlib (lightweight, built into Foundation)
        let compressedData = try compress(jsonData)

        // Write to file
        try compressedData.write(to: url, options: .atomic)
    }

    // MARK: - Load

    /// Load score from .cnb file
    func load(from url: URL) throws -> CNBContainer {
        let compressedData = try Data(contentsOf: url)

        // Decompress
        let jsonData = try decompress(compressedData)

        // Decode
        let container = try decoder.decode(CNBContainer.self, from: jsonData)

        // Version check — migrate if needed
        if container.metadata.formatVersion > CNBFormatVersion.current.rawValue {
            throw CNBError.unsupportedVersion(container.metadata.formatVersion)
        }

        return container
    }

    // MARK: - File Operations

    /// Default save directory (Documents)
    var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Generate URL for a score
    func fileURL(for score: Score) -> URL {
        let safeName = score.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let fileName = safeName.isEmpty ? "Untitled" : safeName
        return documentsDirectory.appendingPathComponent("\(fileName).cnb")
    }

    /// List all .cnb files in Documents
    func listFiles() -> [URL] {
        let docs = documentsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "cnb" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return date1 > date2
            }
    }

    /// Delete a .cnb file
    func delete(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// Quick metadata read without full decode
    func readMetadata(from url: URL) throws -> CNBMetadata {
        let container = try load(from: url)
        return container.metadata
    }

    // MARK: - Compression (zlib via NSData)

    private func compress(_ data: Data) throws -> Data {
        let compressed: Data
        do {
            compressed = try (data as NSData).compressed(using: .zlib) as Data
        } catch {
            throw CNBError.compressionFailed
        }
        // Prepend magic bytes "CNB1" for format identification
        var result = Data("CNB1".utf8)
        result.append(compressed)
        return result
    }

    private func decompress(_ data: Data) throws -> Data {
        // Check magic bytes
        guard data.count > 4 else { throw CNBError.invalidFile }
        let magic = String(data: data.prefix(4), encoding: .utf8)
        guard magic == "CNB1" else {
            // Try reading as plain JSON (backwards compat with autosave)
            if let _ = try? decoder.decode(CNBContainer.self, from: data) {
                return data
            }
            throw CNBError.invalidFile
        }

        let compressedSlice = data.dropFirst(4)
        let decompressed: Data
        do {
            decompressed = try (compressedSlice as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw CNBError.decompressionFailed
        }
        return decompressed
    }
}

// MARK: - Errors

enum CNBError: LocalizedError {
    case invalidFile
    case unsupportedVersion(Int)
    case compressionFailed
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "This is not a valid Composer's Notebook file."
        case .unsupportedVersion(let v):
            return "This file was created with a newer version (v\(v)). Please update the app."
        case .compressionFailed:
            return "Failed to compress file data."
        case .decompressionFailed:
            return "Failed to decompress file data."
        }
    }
}
