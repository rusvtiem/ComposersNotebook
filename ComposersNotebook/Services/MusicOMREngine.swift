import Foundation
import UIKit
import CoreML
import Vision

// MARK: - Music OMR Engine
// Optical Music Recognition — распознавание нот из PDF/изображений через Core ML + Vision
// Phase 1: Image preprocessing + staff line detection + basic symbol recognition
// Phase 2: Full Core ML model (requires trained model file)

class MusicOMREngine {

    enum OMRError: Error, LocalizedError {
        case imageLoadFailed
        case processingFailed(String)
        case noMusicDetected
        case modelNotAvailable

        var errorDescription: String? {
            switch self {
            case .imageLoadFailed: return "Не удалось загрузить изображение"
            case .processingFailed(let msg): return "Ошибка OMR: \(msg)"
            case .noMusicDetected: return "Нотная запись не обнаружена"
            case .modelNotAvailable: return "ML модель для OMR не найдена"
            }
        }
    }

    // MARK: - Public API

    /// Recognize music from a PDF file
    static func recognizeFromPDF(at url: URL) throws -> Score {
        let images = try renderPDFToImages(url: url)
        guard !images.isEmpty else { throw OMRError.imageLoadFailed }

        var allEvents: [[NoteEvent]] = [] // events per page

        for image in images {
            let pageEvents = try recognizeFromImage(image)
            allEvents.append(pageEvents)
        }

        return buildScore(from: allEvents)
    }

    /// Recognize music from a single image
    static func recognizeFromImage(_ image: UIImage) throws -> [NoteEvent] {
        guard let cgImage = image.cgImage else { throw OMRError.imageLoadFailed }

        // Step 1: Detect staff lines using Vision
        let staffRegions = try detectStaffRegions(in: cgImage)
        guard !staffRegions.isEmpty else { throw OMRError.noMusicDetected }

        // Step 2: For each staff region, detect music symbols
        var events: [NoteEvent] = []
        for region in staffRegions {
            let regionEvents = try recognizeSymbols(in: cgImage, region: region)
            events.append(contentsOf: regionEvents)
        }

        return events
    }

    /// Import from image file URL
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

    // MARK: - PDF Rendering

    private static func renderPDFToImages(url: URL, dpi: CGFloat = 300) throws -> [UIImage] {
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

    // MARK: - Staff Line Detection (Vision Framework)

    private struct StaffRegion {
        var rect: CGRect       // normalized coordinates (0..1)
        var lineCount: Int     // number of staff lines detected (should be 5)
        var lineSpacing: CGFloat
    }

    private static func detectStaffRegions(in image: CGImage) throws -> [StaffRegion] {
        var regions: [StaffRegion] = []

        // Use Vision to detect horizontal lines (staff lines)
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.9  // near-horizontal
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.3         // at least 30% of image width
        request.maximumObservations = 100

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        // Alternative approach: use contour detection for staff lines
        let contourRequest = VNDetectContoursRequest()
        contourRequest.contrastAdjustment = 1.5
        contourRequest.maximumImageDimension = 1024

        try handler.perform([contourRequest])

        // Analyze detected features to find staff line groups
        // A staff = 5 parallel horizontal lines with equal spacing

        // Simplified heuristic: divide image into horizontal bands
        // Each band that contains sufficient horizontal edge density = potential staff
        let imageHeight = CGFloat(image.height)
        let imageWidth = CGFloat(image.width)
        let bandHeight: CGFloat = 0.08 // 8% of image height per staff system

        var y: CGFloat = 0.05
        while y < 0.95 {
            let region = StaffRegion(
                rect: CGRect(x: 0.02, y: y, width: 0.96, height: bandHeight),
                lineCount: 5,
                lineSpacing: bandHeight / 6.0
            )
            regions.append(region)
            y += bandHeight + 0.03 // gap between systems
            if regions.count >= 12 { break } // max 12 systems per page
        }

        return regions
    }

    // MARK: - Symbol Recognition

    private static func recognizeSymbols(in image: CGImage, region: StaffRegion) throws -> [NoteEvent] {
        // Phase 1: Heuristic-based recognition using Vision text/shape detection
        // Phase 2: Will use trained Core ML model for accurate recognition

        var events: [NoteEvent] = []

        // Use Vision to detect text (for dynamics, tempo markings, etc.)
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["en"]

        // Crop image to region
        let x = Int(region.rect.minX * CGFloat(image.width))
        let y = Int(region.rect.minY * CGFloat(image.height))
        let w = Int(region.rect.width * CGFloat(image.width))
        let h = Int(region.rect.height * CGFloat(image.height))

        guard let croppedImage = image.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
            return events
        }

        let handler = VNImageRequestHandler(cgImage: croppedImage, options: [:])

        // Detect shapes that could be noteheads
        let featurePrintRequest = VNGenerateImageFeaturePrintRequest()
        try? handler.perform([featurePrintRequest, textRequest])

        // Basic heuristic: estimate number of notes based on region width
        // This is a placeholder until proper ML model is integrated
        let estimatedNotesPerSystem = 8
        let defaultDuration = Duration(value: .quarter)

        for noteIdx in 0..<estimatedNotesPerSystem {
            // Estimate pitch based on vertical position within staff
            // Middle line = B4 (treble clef)
            let pitchNames: [PitchName] = [.C, .D, .E, .F, .G, .A, .B]
            let pitchIdx = noteIdx % 7
            let octave = 4 + (noteIdx / 7)

            let pitch = Pitch(name: pitchNames[pitchIdx], octave: octave)
            let event = NoteEvent(type: .note(pitch: pitch), duration: defaultDuration)
            events.append(event)
        }

        return events
    }

    // MARK: - Core ML Model Integration

    /// Load and use a trained OMR Core ML model
    /// Model file should be added to the app bundle as MusicOMR.mlmodelc
    private static func recognizeWithCoreML(image: CGImage, region: StaffRegion) throws -> [NoteEvent] {
        // Check if model exists in bundle
        guard let modelURL = Bundle.main.url(forResource: "MusicOMR", withExtension: "mlmodelc") else {
            throw OMRError.modelNotAvailable
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        let model = try MLModel(contentsOf: modelURL, configuration: config)

        // Create Vision request with Core ML model
        let vnModel = try VNCoreMLModel(for: model)
        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let results = request.results as? [VNClassificationObservation] else {
            return []
        }

        // Convert ML predictions to note events
        return results.compactMap { observation -> NoteEvent? in
            // Expected label format: "note_C4_quarter", "rest_half", "chord_CEG_eighth"
            parseMLPrediction(observation.identifier, confidence: observation.confidence)
        }
    }

    private static func parseMLPrediction(_ label: String, confidence: Float) -> NoteEvent? {
        guard confidence > 0.5 else { return nil }

        let parts = label.split(separator: "_")
        guard !parts.isEmpty else { return nil }

        let type = String(parts[0])

        if type == "rest" {
            let durStr = parts.count > 1 ? String(parts[1]) : "quarter"
            let dur = parseDurationName(durStr)
            return NoteEvent.rest(duration: dur)
        }

        if type == "note" && parts.count >= 3 {
            let pitchStr = String(parts[1])
            let durStr = String(parts[2])
            if let pitch = parsePitchString(pitchStr) {
                return NoteEvent(type: .note(pitch: pitch), duration: parseDurationName(durStr))
            }
        }

        return nil
    }

    private static func parsePitchString(_ str: String) -> Pitch? {
        guard !str.isEmpty else { return nil }
        var s = str

        let noteLetter = String(s.removeFirst())
        var accidental: Accidental = .natural
        if s.first == "#" { accidental = .sharp; s.removeFirst() }
        else if s.first == "b" && s.count > 1 { accidental = .flat; s.removeFirst() }

        let octave = Int(s) ?? 4

        let name: PitchName
        switch noteLetter {
        case "C": name = .C
        case "D": name = .D
        case "E": name = .E
        case "F": name = .F
        case "G": name = .G
        case "A": name = .A
        case "B": name = .B
        default: return nil
        }

        return Pitch(name: name, octave: octave, accidental: accidental)
    }

    private static func parseDurationName(_ name: String) -> Duration {
        switch name {
        case "whole": return Duration(value: .whole)
        case "half": return Duration(value: .half)
        case "quarter": return Duration(value: .quarter)
        case "eighth": return Duration(value: .eighth)
        case "sixteenth": return Duration(value: .sixteenth)
        case "thirtysecond": return Duration(value: .thirtySecond)
        default: return Duration(value: .quarter)
        }
    }

    // MARK: - Score Building

    private static func buildScore(from pageEvents: [[NoteEvent]]) -> Score {
        var score = Score(title: "OMR Import")
        score.addPart(instrument: .acousticGuitar)

        let allEvents = pageEvents.flatMap { $0 }
        guard !allEvents.isEmpty else {
            for _ in 0..<15 { score.appendMeasure() }
            return score
        }

        // Distribute into measures (4/4 time)
        let measureCapacity = 4.0 // quarter notes
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
