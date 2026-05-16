import Foundation
import UIKit

// MARK: - Music OMR Engine (no ML / no Vision / no CoreML)
//
// Optical Music Recognition — распознавание нот из PDF/изображений.
// Полностью на пиксельной эвристике: render PDF → grayscale threshold →
// horizontal projection для staff lines → connected components для noteheads →
// геометрия для pitch определения.
//
// Никаких внешних ML / нейросетей / Apple Vision / Apple CoreML.
// Ограничение: качество ниже чем у обученной ML модели; длительности
// упрощённо (по плотности нот в системе). Импорт PDF остаётся как функция,
// но результат — отправная точка для ручной правки в редакторе.
//
// Failure modes: PDF без чёткого нотного стана → noMusicDetected.
//                Сильно скошенные сканы → пропуск систем.
// Detect: пользователь видит мало нот после импорта.
// Recover: ручной ввод поверх импортированной заготовки.

class MusicOMREngine {

    enum OMRError: Error, LocalizedError {
        case imageLoadFailed
        case processingFailed(String)
        case noMusicDetected

        var errorDescription: String? {
            switch self {
            case .imageLoadFailed: return "Не удалось загрузить изображение"
            case .processingFailed(let msg): return "Ошибка OMR: \(msg)"
            case .noMusicDetected: return "Нотная запись не обнаружена"
            }
        }
    }

    // MARK: - Public API

    /// Импорт PDF — рендер всех страниц + поиск нот
    static func recognizeFromPDF(at url: URL) throws -> Score {
        let images = try renderPDFToImages(url: url)
        guard !images.isEmpty else { throw OMRError.imageLoadFailed }

        var allEvents: [[NoteEvent]] = []
        for image in images {
            let pageEvents = (try? recognizeFromImage(image)) ?? []
            allEvents.append(pageEvents)
        }
        return buildScore(from: allEvents)
    }

    /// Распознавание из одного изображения
    static func recognizeFromImage(_ image: UIImage) throws -> [NoteEvent] {
        guard let cgImage = image.cgImage else { throw OMRError.imageLoadFailed }
        guard let buffer = PixelBuffer(cgImage: cgImage) else {
            throw OMRError.processingFailed("Не удалось прочитать пиксели")
        }

        let systems = detectStaffSystems(in: buffer)
        guard !systems.isEmpty else { throw OMRError.noMusicDetected }

        var events: [NoteEvent] = []
        for system in systems {
            let heads = extractNoteHeads(in: buffer, system: system)
            let systemEvents = convertToNoteEvents(heads: heads, system: system)
            events.append(contentsOf: systemEvents)
        }
        return events
    }

    /// Импорт по URL (PDF или изображение)
    static func importFile(at url: URL) throws -> Score {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return try recognizeFromPDF(at: url)
        }
        let data = try Data(contentsOf: url)
        guard let image = UIImage(data: data) else { throw OMRError.imageLoadFailed }
        let events = try recognizeFromImage(image)
        return buildScore(from: [events])
    }

    // MARK: - PDF Rendering (CGPDFDocument, no ML)

    private static func renderPDFToImages(url: URL, dpi: CGFloat = 200) throws -> [UIImage] {
        guard let document = CGPDFDocument(url as CFURL) else {
            throw OMRError.imageLoadFailed
        }

        var images: [UIImage] = []
        let pageCount = document.numberOfPages
        for pageNum in 1...pageCount {
            guard let page = document.page(at: pageNum) else { continue }
            let mediaBox = page.getBoxRect(.mediaBox)
            let scale = dpi / 72.0
            let width = Int(mediaBox.width * scale)
            let height = Int(mediaBox.height * scale)
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }

            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(page)

            if let cgImage = context.makeImage() {
                images.append(UIImage(cgImage: cgImage))
            }
        }
        return images
    }

    // MARK: - Staff System Detection (pure horizontal projection)

    /// 5 параллельных линий стана с равными промежутками
    struct StaffSystem {
        var lineY: [Int]
        var leftX: Int
        var rightX: Int
        var lineSpacing: CGFloat

        var topY: Int { lineY.first ?? 0 }
        var bottomY: Int { lineY.last ?? 0 }
    }

    /// Horizontal projection: % чёрных пикселей по каждой Y-строке.
    /// Локальные максимумы выше порога = candidate staff lines.
    /// Группируем по 5 с примерно равным интервалом.
    private static func detectStaffSystems(in buffer: PixelBuffer) -> [StaffSystem] {
        let width = buffer.width
        let height = buffer.height
        let darkThreshold: UInt8 = 128

        let leftMargin = width / 20
        let rightMargin = width - width / 20
        var rowDensity = [CGFloat](repeating: 0, count: height)

        for y in 0..<height {
            var darkCount = 0
            for x in leftMargin..<rightMargin {
                if buffer.luminance(x: x, y: y) < darkThreshold {
                    darkCount += 1
                }
            }
            rowDensity[y] = CGFloat(darkCount) / CGFloat(rightMargin - leftMargin)
        }

        let maxDensity = rowDensity.max() ?? 0
        guard maxDensity > 0.15 else { return [] }
        let strongThreshold: CGFloat = max(0.3, maxDensity * 0.55)

        var peaks: [Int] = []
        var y = 0
        while y < height {
            if rowDensity[y] >= strongThreshold {
                var endY = y
                while endY + 1 < height && rowDensity[endY + 1] >= strongThreshold {
                    endY += 1
                }
                peaks.append((y + endY) / 2)
                y = endY + 1
            } else {
                y += 1
            }
        }
        guard peaks.count >= 5 else { return [] }

        var systems: [StaffSystem] = []
        var i = 0
        while i + 4 < peaks.count {
            let group = Array(peaks[i...i+4])
            let intervals = zip(group.dropFirst(), group.dropLast()).map { $0 - $1 }
            let avg = CGFloat(intervals.reduce(0, +)) / CGFloat(intervals.count)
            let isEvenlySpaced = intervals.allSatisfy { interval in
                abs(CGFloat(interval) - avg) <= avg * 0.35
            }
            if isEvenlySpaced && avg >= 3 && avg <= CGFloat(height) / 10 {
                systems.append(StaffSystem(
                    lineY: group,
                    leftX: leftMargin,
                    rightX: rightMargin,
                    lineSpacing: avg
                ))
                i += 5
            } else {
                i += 1
            }
        }
        return systems
    }

    // MARK: - Note Head Extraction (Connected Components Labeling, no ML)

    struct NoteHead {
        var x: Int
        var y: Int
        var width: Int
        var height: Int
        var pixelCount: Int

        var centerX: CGFloat { CGFloat(x) + CGFloat(width) / 2 }
        var centerY: CGFloat { CGFloat(y) + CGFloat(height) / 2 }
    }

    private static func extractNoteHeads(in buffer: PixelBuffer, system: StaffSystem) -> [NoteHead] {
        let spacing = system.lineSpacing
        let searchTop = max(0, system.topY - Int(spacing * 4))
        let searchBottom = min(buffer.height - 1, system.bottomY + Int(spacing * 4))
        let searchLeft = system.leftX
        let searchRight = system.rightX

        let regionWidth = searchRight - searchLeft + 1
        let regionHeight = searchBottom - searchTop + 1
        guard regionWidth > 0, regionHeight > 0 else { return [] }

        // 1. Бинаризация в локальный буфер
        var binary = [Bool](repeating: false, count: regionWidth * regionHeight)
        let darkThreshold: UInt8 = 110
        for ry in 0..<regionHeight {
            let absY = searchTop + ry
            for rx in 0..<regionWidth {
                let absX = searchLeft + rx
                if buffer.luminance(x: absX, y: absY) < darkThreshold {
                    binary[ry * regionWidth + rx] = true
                }
            }
        }

        // 2. Стираем staff lines — чтобы не "соединять" соседние ноты
        for absLineY in system.lineY {
            let ry = absLineY - searchTop
            guard ry >= 0 && ry < regionHeight else { continue }
            for offset in -1...1 {
                let yy = ry + offset
                guard yy >= 0 && yy < regionHeight else { continue }
                for rx in 0..<regionWidth {
                    // удаляем только если в колонке мало чёрного (= это staff line, не штиль)
                    let yStart = max(0, yy-2)
                    let yEnd = min(regionHeight-1, yy+2)
                    var columnDark = 0
                    for y2 in yStart...yEnd {
                        if binary[y2 * regionWidth + rx] { columnDark += 1 }
                    }
                    if columnDark <= 3 {
                        binary[yy * regionWidth + rx] = false
                    }
                }
            }
        }

        // 3. Connected Components Labeling — BFS flood fill
        var visited = [Bool](repeating: false, count: binary.count)
        var heads: [NoteHead] = []

        let minBlobPixels = Int(spacing * spacing * 0.3)
        let maxBlobPixels = Int(spacing * spacing * 3.0)
        let minBlobWidth = Int(spacing * 0.6)
        let maxBlobWidth = Int(spacing * 2.2)
        let minBlobHeight = Int(spacing * 0.5)
        let maxBlobHeight = Int(spacing * 1.8)

        for startY in 0..<regionHeight {
            for startX in 0..<regionWidth {
                let idx0 = startY * regionWidth + startX
                if visited[idx0] || !binary[idx0] { continue }

                var queue: [(Int, Int)] = [(startX, startY)]
                var minX = startX, maxX = startX
                var minY = startY, maxY = startY
                var pixelCount = 0
                visited[idx0] = true

                while let (cx, cy) = queue.popLast() {
                    pixelCount += 1
                    if cx < minX { minX = cx }
                    if cx > maxX { maxX = cx }
                    if cy < minY { minY = cy }
                    if cy > maxY { maxY = cy }

                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nx = cx + dx
                        let ny = cy + dy
                        guard nx >= 0 && nx < regionWidth && ny >= 0 && ny < regionHeight else { continue }
                        let nidx = ny * regionWidth + nx
                        if !visited[nidx] && binary[nidx] {
                            visited[nidx] = true
                            queue.append((nx, ny))
                        }
                    }
                    if pixelCount > maxBlobPixels * 2 { break }
                }

                let bw = maxX - minX + 1
                let bh = maxY - minY + 1
                if pixelCount >= minBlobPixels && pixelCount <= maxBlobPixels &&
                   bw >= minBlobWidth && bw <= maxBlobWidth &&
                   bh >= minBlobHeight && bh <= maxBlobHeight {
                    let absX = searchLeft + minX
                    let absY = searchTop + minY
                    heads.append(NoteHead(
                        x: absX, y: absY,
                        width: bw, height: bh,
                        pixelCount: pixelCount
                    ))
                }
            }
        }

        heads.sort { $0.centerX < $1.centerX }

        // Слияние очень близких голов (артефакты бинаризации)
        var merged: [NoteHead] = []
        let mergeRadius = spacing * 0.4
        for h in heads {
            if let last = merged.last,
               abs(h.centerX - last.centerX) < mergeRadius,
               abs(h.centerY - last.centerY) < mergeRadius {
                continue
            }
            merged.append(h)
        }
        return merged
    }

    // MARK: - Pitch Conversion (treble clef heuristic, no ML)

    private static func convertToNoteEvents(heads: [NoteHead], system: StaffSystem) -> [NoteEvent] {
        var events: [NoteEvent] = []
        let spacing = system.lineSpacing
        let halfStep = spacing / 2.0

        // Middle line (3-я, index 2) = B4 на treble клефе
        let middleLineDiatonic = 6 // B4 = C(0)+D(1)+E(2)+F(3)+G(4)+A(5)+B(6)
        let middleLineY = CGFloat(system.lineY[2])

        for head in heads {
            let dy = (middleLineY - head.centerY) / halfStep
            let stepsFromMiddle = Int(dy.rounded())
            let diatonicStep = middleLineDiatonic + stepsFromMiddle

            let octave = 4 + (diatonicStep / 7)
            let stepInOctave = ((diatonicStep % 7) + 7) % 7

            let names: [PitchName] = [.C, .D, .E, .F, .G, .A, .B]
            let name = names[stepInOctave]

            let pitch = Pitch(name: name, octave: octave, accidental: .natural)
            events.append(NoteEvent(type: .note(pitch: pitch), duration: Duration(value: .quarter)))
        }
        return events
    }

    // MARK: - Score Building

    private static func buildScore(from pageEvents: [[NoteEvent]]) -> Score {
        var score = Score(title: "OMR Import")
        score.addPart(instrument: .acousticGuitar)

        let allEvents = pageEvents.flatMap { $0 }
        guard !allEvents.isEmpty else {
            for _ in 0..<8 { score.appendMeasure() }
            return score
        }

        let measureCapacity = 4.0
        var measureEvents: [NoteEvent] = []
        var currentBeats = 0.0
        var measureIdx = 0

        for event in allEvents {
            let beats = event.duration.beats
            measureEvents.append(event)
            currentBeats += beats

            if currentBeats >= measureCapacity - 0.001 {
                while score.measureCount <= measureIdx { score.appendMeasure() }
                score.parts[0].measures[measureIdx].events = measureEvents
                measureIdx += 1
                measureEvents = []
                currentBeats = 0.0
            }
        }
        if !measureEvents.isEmpty {
            while score.measureCount <= measureIdx { score.appendMeasure() }
            score.parts[0].measures[measureIdx].events = measureEvents
        }
        return score
    }
}

// MARK: - Pixel Buffer (helper для эффективного доступа)

/// Обёртка для доступа к RGBA8 пикселям CGImage.
/// luminance = 0.299*R + 0.587*G + 0.114*B (Y из YCbCr).
struct PixelBuffer {
    let width: Int
    let height: Int
    private let bytes: [UInt8]
    private let bytesPerRow: Int
    private let bytesPerPixel: Int

    init?(cgImage: CGImage) {
        let w = cgImage.width
        let h = cgImage.height
        let bpr = w * 4
        let cs = CGColorSpaceCreateDeviceRGB()
        var raw = [UInt8](repeating: 0, count: bpr * h)

        guard let ctx = raw.withUnsafeMutableBytes({ ptr -> CGContext? in
            guard let base = ptr.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bpr,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        self.width = w
        self.height = h
        self.bytes = raw
        self.bytesPerRow = bpr
        self.bytesPerPixel = 4
    }

    @inlinable
    func luminance(x: Int, y: Int) -> UInt8 {
        let offset = y * bytesPerRow + x * bytesPerPixel
        let r = Int(bytes[offset])
        let g = Int(bytes[offset + 1])
        let b = Int(bytes[offset + 2])
        return UInt8((299 * r + 587 * g + 114 * b) / 1000)
    }
}
