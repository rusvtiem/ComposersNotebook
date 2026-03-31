import UIKit
import PDFKit

// MARK: - PDF Exporter
// Renders score to professional PDF using UIGraphics

class PDFExporter {

    // MARK: - Configuration

    struct Config {
        var pageSize: CGSize = CGSize(width: 595, height: 842) // A4
        var margin: CGFloat = 50
        var staffLineSpacing: CGFloat = 8
        var measureWidth: CGFloat = 180
        var titleFontSize: CGFloat = 24
        var composerFontSize: CGFloat = 14
        var instrumentFontSize: CGFloat = 10
        var noteHeadRadius: CGFloat = 4
        var stemLength: CGFloat = 28
        var partSpacing: CGFloat = 60

        var contentWidth: CGFloat { pageSize.width - margin * 2 }
        var measuresPerLine: Int { max(1, Int(contentWidth / measureWidth)) }
        var staffHeight: CGFloat { staffLineSpacing * 4 }
    }

    // MARK: - Public API

    /// Export score to PDF data
    static func export(score: Score, config: Config = Config()) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: config.pageSize))

        return renderer.pdfData { context in
            let exporter = PDFExporter(score: score, config: config, context: context)
            exporter.render()
        }
    }

    /// Export score to PDF file
    static func exportToFile(score: Score, url: URL, config: Config = Config()) throws {
        let data = export(score: score, config: config)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Private

    private let score: Score
    private let config: Config
    private let pdfContext: UIGraphicsPDFRendererContext
    private var currentY: CGFloat = 0

    private init(score: Score, config: Config, context: UIGraphicsPDFRendererContext) {
        self.score = score
        self.config = config
        self.pdfContext = context
    }

    private func render() {
        startNewPage()
        drawTitle()

        guard let firstPart = score.parts.first else { return }
        let totalMeasures = firstPart.measures.count

        // Render in systems (lines of measures)
        var measureIndex = 0
        while measureIndex < totalMeasures {
            let measuresInLine = min(config.measuresPerLine, totalMeasures - measureIndex)

            // Check if system fits on current page
            let systemHeight = CGFloat(score.parts.count) * (config.staffHeight + config.partSpacing)
            if currentY + systemHeight > config.pageSize.height - config.margin {
                startNewPage()
            }

            drawSystem(startMeasure: measureIndex, count: measuresInLine)
            measureIndex += measuresInLine
            currentY += 20 // spacing between systems
        }
    }

    // MARK: - Page Management

    private func startNewPage() {
        pdfContext.beginPage()
        currentY = config.margin
    }

    // MARK: - Title Block

    private func drawTitle() {
        let titleFont = UIFont.boldSystemFont(ofSize: config.titleFontSize)
        let composerFont = UIFont.italicSystemFont(ofSize: config.composerFontSize)

        // Title centered
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]
        let titleSize = score.title.size(withAttributes: titleAttrs)
        let titleX = (config.pageSize.width - titleSize.width) / 2
        score.title.draw(at: CGPoint(x: titleX, y: currentY), withAttributes: titleAttrs)
        currentY += titleSize.height + 4

        // Composer right-aligned
        if !score.composer.isEmpty {
            let composerAttrs: [NSAttributedString.Key: Any] = [
                .font: composerFont,
                .foregroundColor: UIColor.darkGray
            ]
            let composerSize = score.composer.size(withAttributes: composerAttrs)
            let composerX = config.pageSize.width - config.margin - composerSize.width
            score.composer.draw(at: CGPoint(x: composerX, y: currentY), withAttributes: composerAttrs)
            currentY += composerSize.height
        }

        currentY += 20 // space after title block
    }

    // MARK: - System (one line of measures for all parts)

    private func drawSystem(startMeasure: Int, count: Int) {
        let ctx = UIGraphicsGetCurrentContext()!
        let lineWidth = CGFloat(count) * config.measureWidth

        for (partIdx, part) in score.parts.enumerated() {
            let staffTop = currentY + CGFloat(partIdx) * (config.staffHeight + config.partSpacing)

            // Draw instrument name (first system only)
            if startMeasure == 0 {
                let nameFont = UIFont.systemFont(ofSize: config.instrumentFontSize)
                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: nameFont,
                    .foregroundColor: UIColor.black
                ]
                let name = part.instrument.shortName
                let nameSize = name.size(withAttributes: nameAttrs)
                name.draw(
                    at: CGPoint(x: config.margin - nameSize.width - 5, y: staffTop + config.staffHeight / 2 - nameSize.height / 2),
                    withAttributes: nameAttrs
                )
            }

            // Draw staff lines
            ctx.setStrokeColor(UIColor.black.cgColor)
            ctx.setLineWidth(0.5)

            for line in 0..<5 {
                let y = staffTop + CGFloat(line) * config.staffLineSpacing
                ctx.move(to: CGPoint(x: config.margin, y: y))
                ctx.addLine(to: CGPoint(x: config.margin + lineWidth, y: y))
            }
            ctx.strokePath()

            // Draw clef (first measure of first system)
            if startMeasure == 0 {
                drawClef(part.clef, at: CGPoint(x: config.margin + 5, y: staffTop), ctx: ctx)
            }

            // Draw measures
            for mOffset in 0..<count {
                let mIdx = startMeasure + mOffset
                guard mIdx < part.measures.count else { break }
                let measure = part.measures[mIdx]
                let measureX = config.margin + CGFloat(mOffset) * config.measureWidth

                drawMeasure(measure, at: measureX, staffTop: staffTop, measureIndex: mIdx, ctx: ctx)

                // Barline
                let barX = measureX + config.measureWidth
                ctx.setLineWidth(measure.barlineEnd == .final_ ? 2 : 0.5)
                ctx.move(to: CGPoint(x: barX, y: staffTop))
                ctx.addLine(to: CGPoint(x: barX, y: staffTop + config.staffHeight))
                ctx.strokePath()
            }
        }

        // System brace / barline (left side)
        if score.parts.count > 1 {
            let topStaff = currentY
            let bottomStaff = currentY + CGFloat(score.parts.count - 1) * (config.staffHeight + config.partSpacing) + config.staffHeight

            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: config.margin, y: topStaff))
            ctx.addLine(to: CGPoint(x: config.margin, y: bottomStaff))
            ctx.strokePath()
        }

        currentY += CGFloat(score.parts.count) * (config.staffHeight + config.partSpacing)
    }

    // MARK: - Measure Drawing

    private func drawMeasure(_ measure: Measure, at x: CGFloat, staffTop: CGFloat, measureIndex: Int, ctx: CGContext) {
        let ts = measure.timeSignature ?? score.timeSignature
        let noteAreaWidth = config.measureWidth - 10
        let totalBeats = ts.totalBeats
        var beatPosition: Double = 0

        // Measure number (above first part)
        if measureIndex > 0 && measureIndex % config.measuresPerLine == 0 {
            let numStr = "\(measureIndex + 1)"
            let numFont = UIFont.systemFont(ofSize: 8)
            let numAttrs: [NSAttributedString.Key: Any] = [.font: numFont, .foregroundColor: UIColor.gray]
            numStr.draw(at: CGPoint(x: x + 2, y: staffTop - 12), withAttributes: numAttrs)
        }

        for event in measure.events {
            let noteX = x + 5 + CGFloat(beatPosition / totalBeats) * noteAreaWidth

            if event.isRest {
                drawRest(event.duration, at: CGPoint(x: noteX, y: staffTop + config.staffHeight / 2), ctx: ctx)
            } else {
                for pitch in event.pitches {
                    let noteY = noteY(pitch: pitch, staffTop: staffTop)
                    drawNoteHead(at: CGPoint(x: noteX, y: noteY), duration: event.duration, ctx: ctx)

                    // Ledger lines
                    drawLedgerLines(pitch: pitch, x: noteX, staffTop: staffTop, ctx: ctx)

                    // Accidental
                    if pitch.accidental != .natural {
                        let accStr = pitch.accidental.displaySymbol
                        let accFont = UIFont.systemFont(ofSize: config.noteHeadRadius * 2.5)
                        let accAttrs: [NSAttributedString.Key: Any] = [.font: accFont, .foregroundColor: UIColor.black]
                        accStr.draw(at: CGPoint(x: noteX - config.noteHeadRadius * 3, y: noteY - config.noteHeadRadius * 1.5), withAttributes: accAttrs)
                    }

                    // Stem
                    if event.duration.value != .whole {
                        let stemUp = noteY > staffTop + config.staffHeight / 2
                        drawStem(at: CGPoint(x: noteX, y: noteY), stemUp: stemUp, duration: event.duration, ctx: ctx)
                    }
                }

                // Articulations
                if let firstPitch = event.pitches.first {
                    let noteY = noteY(pitch: firstPitch, staffTop: staffTop)
                    for art in event.articulations {
                        let artY = noteY < staffTop + config.staffHeight / 2
                            ? noteY + config.noteHeadRadius * 4
                            : noteY - config.noteHeadRadius * 4
                        let artFont = UIFont.systemFont(ofSize: 10)
                        let artAttrs: [NSAttributedString.Key: Any] = [.font: artFont, .foregroundColor: UIColor.black]
                        art.displaySymbol.draw(at: CGPoint(x: noteX - 3, y: artY - 5), withAttributes: artAttrs)
                    }
                }

                // Dynamic marking
                if let dyn = event.dynamic {
                    let dynFont = UIFont.italicSystemFont(ofSize: 9)
                    let dynAttrs: [NSAttributedString.Key: Any] = [.font: dynFont, .foregroundColor: UIColor.black]
                    let dynY = staffTop + config.staffHeight + 8
                    "\(dyn)".draw(at: CGPoint(x: noteX - 4, y: dynY), withAttributes: dynAttrs)
                }
            }

            beatPosition += event.duration.beats
        }

        // Tempo marking
        if let tempo = measure.tempoMarking {
            let tempoFont = UIFont.boldSystemFont(ofSize: 9)
            let tempoAttrs: [NSAttributedString.Key: Any] = [.font: tempoFont, .foregroundColor: UIColor.black]
            tempo.displayString.draw(at: CGPoint(x: x + 2, y: staffTop - 14), withAttributes: tempoAttrs)
        }
    }

    // MARK: - Drawing Primitives

    private func noteY(pitch: Pitch, staffTop: CGFloat) -> CGFloat {
        // B5 = top line (treble clef), maps staffPosition to Y
        let middleLine = staffTop + config.staffHeight / 2 // B4 in treble
        let stepsFromB4 = pitch.staffPosition - Pitch(name: .B, octave: 4).staffPosition
        return middleLine - CGFloat(stepsFromB4) * config.staffLineSpacing / 2
    }

    private func drawNoteHead(at point: CGPoint, duration: Duration, ctx: CGContext) {
        let r = config.noteHeadRadius
        let rect = CGRect(x: point.x - r, y: point.y - r * 0.75, width: r * 2, height: r * 1.5)

        ctx.saveGState()
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.setStrokeColor(UIColor.black.cgColor)
        ctx.setLineWidth(0.8)

        // Rotate slightly for more natural look
        ctx.translateBy(x: point.x, y: point.y)
        ctx.rotate(by: -0.15)
        ctx.translateBy(x: -point.x, y: -point.y)

        let path = UIBezierPath(ovalIn: rect)

        if duration.value == .whole || duration.value == .half {
            path.stroke()
        } else {
            path.fill()
        }

        ctx.restoreGState()
    }

    private func drawStem(at point: CGPoint, stemUp: Bool, duration: Duration, ctx: CGContext) {
        let r = config.noteHeadRadius
        ctx.setStrokeColor(UIColor.black.cgColor)
        ctx.setLineWidth(0.8)

        let startX = stemUp ? point.x + r : point.x - r
        let startY = point.y
        let endY = stemUp ? startY - config.stemLength : startY + config.stemLength

        ctx.move(to: CGPoint(x: startX, y: startY))
        ctx.addLine(to: CGPoint(x: startX, y: endY))
        ctx.strokePath()

        // Flags
        let flagCount: Int = {
            switch duration.value {
            case .eighth: return 1
            case .sixteenth: return 2
            case .thirtySecond: return 3
            default: return 0
            }
        }()

        for i in 0..<flagCount {
            let flagY = endY + (stemUp ? CGFloat(i) * 6 : -CGFloat(i) * 6)
            let flagEndX = startX + (stemUp ? 8 : -8)
            let flagEndY = flagY + (stemUp ? 8 : -8)

            ctx.move(to: CGPoint(x: startX, y: flagY))
            ctx.addQuadCurve(
                to: CGPoint(x: flagEndX, y: flagEndY),
                control: CGPoint(x: startX + (stemUp ? 10 : -10), y: flagY)
            )
            ctx.setLineWidth(1.2)
            ctx.strokePath()
        }
    }

    private func drawLedgerLines(pitch: Pitch, x: CGFloat, staffTop: CGFloat, ctx: CGContext) {
        let y = noteY(pitch: pitch, staffTop: staffTop)
        let r = config.noteHeadRadius
        let staffBottom = staffTop + config.staffHeight

        ctx.setStrokeColor(UIColor.black.cgColor)
        ctx.setLineWidth(0.5)

        // Above staff
        if y < staffTop {
            var lineY = staffTop - config.staffLineSpacing
            while lineY >= y - config.staffLineSpacing / 2 {
                ctx.move(to: CGPoint(x: x - r * 1.5, y: lineY))
                ctx.addLine(to: CGPoint(x: x + r * 1.5, y: lineY))
                lineY -= config.staffLineSpacing
            }
            ctx.strokePath()
        }

        // Below staff
        if y > staffBottom {
            var lineY = staffBottom + config.staffLineSpacing
            while lineY <= y + config.staffLineSpacing / 2 {
                ctx.move(to: CGPoint(x: x - r * 1.5, y: lineY))
                ctx.addLine(to: CGPoint(x: x + r * 1.5, y: lineY))
                lineY += config.staffLineSpacing
            }
            ctx.strokePath()
        }
    }

    private func drawRest(_ duration: Duration, at point: CGPoint, ctx: CGContext) {
        let restStr: String = {
            switch duration.value {
            case .whole: return "𝄻"
            case .half: return "𝄼"
            case .quarter: return "𝄾"
            case .eighth: return "𝄿"
            case .sixteenth: return "𝅀"
            case .thirtySecond: return "𝅁"
            }
        }()

        let font = UIFont.systemFont(ofSize: 20)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let size = restStr.size(withAttributes: attrs)
        restStr.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attrs)
    }

    private func drawClef(_ clef: Clef, at point: CGPoint, ctx: CGContext) {
        let clefStr: String = {
            switch clef {
            case .treble: return "𝄞"
            case .bass: return "𝄢"
            case .alto, .tenor: return "𝄡"
            }
        }()

        let font = UIFont.systemFont(ofSize: 32)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        clefStr.draw(at: CGPoint(x: point.x, y: point.y - 8), withAttributes: attrs)
    }
}
