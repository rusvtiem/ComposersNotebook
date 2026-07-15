import SwiftUI
import WebKit

/// The main editor's staff, engraved by the real Verovio engine instead of the
/// homemade `EngravingEngine`/Canvas. This is the "fully embed the engine" step:
/// the working editor screen draws through Verovio, so the two layout bugs of the
/// homemade engine (grand-staff staves diverging in height, a lone measure
/// stretched full width) are gone — Verovio lays out by professional rules.
///
/// Input is unchanged: the existing toolbar `inputMode` drives what a tap does —
/// `.note` adds a note at the pitch under the finger, `.rest` inserts a rest at
/// the cursor, `.navigate` selects the tapped note. The note/letter/piano input
/// areas keep calling the model; every model edit bumps `score.modifiedAt`, which
/// re-engraves here. Verovio renders in 1.5–8.6 ms, fast enough to redraw inline.
///
/// The homemade `StaffAreaView` stays in the codebase and is reachable as a
/// fallback (Settings → classic renderer) so a Verovio failure never bricks the
/// editor.
///
/// Failure modes:
///   - Verovio not ready / rejects the score -> Detect: `render()` yields nil svg/geometry
///       -> Recover: an inline notice with a hint to switch to the classic renderer; no crash.
///   - Tap resolves no staff (add) -> Detect: `nearestStaff` == nil -> Recover: no-op, nothing inserted.
///   - Tap misses every notehead (select) -> Detect: `note(near:)` == nil -> Recover: no-op deselect.
struct VerovioStaffSurface: View {
    @ObservedObject var viewModel: ScoreViewModel
    /// Observed directly (not through `viewModel`, which stores it as a plain `let`):
    /// SwiftUI does not track nested ObservableObjects, so without this the playback
    /// cursor would not appear on Play or disappear on Stop. Same shared instance.
    @ObservedObject private var midiEngine = MIDIEngine.shared
    /// Width measured by the parent outside the ScrollView (a GeometryReader
    /// nested in a ScrollView collapses to zero height).
    let availableWidth: CGFloat

    /// MuseScore 4 voice-1 / selection blue (#0065BF), from engravingconfiguration.cpp.
    /// Used for the selection ring so it matches the reference editor instead of the
    /// theme-dependent system accent.
    private static let museScoreSelectionBlueHex = "#0065BF"
    private static let museScoreSelectionBlue = Color(hex: museScoreSelectionBlueHex)

    /// MuseScore 4 note-input caret fill — the selection blue at low opacity, so it
    /// reads as the translucent vertical band MuseScore paints on the insertion beat
    /// (a soft blue column, not a hairline).
    private static let noteInputCaret = Color(hex: museScoreSelectionBlueHex).opacity(0.22)

    /// MuseScore 4 accent blue (#2093FE), translucent — the moving playback cursor.
    /// Deliberately lighter and see-through so it reads as a playing-position sweep
    /// (like a video scrubber) and never gets confused with the solid input caret.
    private static let playbackCursor = Color(hex: "#2093FE").opacity(0.45)

    @State private var svg: String?
    @State private var geometry: VerovioSVGGeometry?
    /// Human-readable reason the staff is not showing. Surfaced on-screen so a
    /// blank never happens silently — the message itself explains the recovery.
    @State private var status: String = ""

    var body: some View {
        Group {
            if let svg {
                engraved(svg: svg, geometry: geometry)
            } else {
                unavailable
            }
        }
        .task { render() }
        .onChange(of: viewModel.score.modifiedAt) { _, _ in render() }
        .onChange(of: availableWidth) { _, _ in render() }
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "Cannot engrave"))
                .font(.headline)
            Text(status.isEmpty
                 ? String(localized: "The Verovio engine could not render this score. You can switch to the classic renderer in Settings.")
                 : status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    // MARK: - Engraved staff + tap layer

    private func engraved(svg: String, geometry: VerovioSVGGeometry?) -> some View {
        // The SVG is scaled uniformly to `availableWidth * zoom`; height follows the
        // viewBox aspect (always present once Verovio rendered). A floor keeps the
        // staff visible even if geometry parsing degrades, so the surface never
        // collapses to nothing. One viewBox unit = `contentWidth / viewBox.width`
        // points — the factor mapping a tap back to viewBox coords and a note to screen.
        let contentWidth = availableWidth * viewModel.zoomScale
        let aspect: CGFloat = {
            if let g = geometry, g.viewBox.width > 0 { return g.viewBox.height / g.viewBox.width }
            return 0.28
        }()
        let contentHeight = max(contentWidth * aspect, 120)
        let unitToPoint: CGFloat = {
            if let g = geometry, g.viewBox.width > 0 { return contentWidth / g.viewBox.width }
            return 1
        }()

        // The engraving sits on a real "sheet of paper": a white page with
        // Verovio's own margins, a soft drop shadow, and a neutral desk behind
        // it (added by the parent). This is the MuseScore/Dorico look — the score
        // reads as "notes on a page", not glyphs floating on the app background.
        // Because the page is always white, the ink is always black (a real sheet
        // of music is black-on-white regardless of the app's light/dark theme);
        // the dark-theme staff-visibility path lives on in the classic renderer.
        return ZStack(alignment: .topLeading) {
            SVGWebView(svg: svg, ink: "black",
                       highlightIDs: selectedExportedIDs,
                       highlightColor: viewModel.selectedEvent?.voice.colorHex ?? Self.museScoreSelectionBlueHex)
                .frame(width: contentWidth, height: contentHeight)

            if let geometry {
                if let caret = cursorCaret(in: geometry) {
                    // MuseScore paints the note-input caret as a translucent blue band
                    // sitting on the insertion beat (full system height), not a hairline.
                    let w = max(caret.width * unitToPoint, 2)
                    let rect = CGRect(x: caret.x * unitToPoint - w / 2,
                                      y: caret.top * unitToPoint,
                                      width: w,
                                      height: (caret.bottom - caret.top) * unitToPoint)
                    Path { path in
                        path.addRoundedRect(in: rect,
                                            cornerSize: CGSize(width: w * 0.2, height: w * 0.2))
                    }
                    .fill(Self.noteInputCaret)
                    .allowsHitTesting(false)
                }

                // Playback cursor: a translucent vertical bar that sweeps the score
                // while it plays (MuseScore's playing-position line, separate from the
                // input caret above). TimelineView(.animation) re-samples every frame,
                // so the bar moves smoothly; it only exists while `isPlaying`, so it
                // vanishes on stop/pause.
                if midiEngine.isPlaying,
                   let start = midiEngine.playbackStartDate,
                   let progress = midiEngine.playbackProgress {
                    TimelineView(.animation) { timeline in
                        let elapsed = timeline.date.timeIntervalSince(start)
                        if let loc = progress.locate(elapsed: elapsed),
                           let line = geometry.playheadLine(measureIndex: loc.measure,
                                                            fraction: CGFloat(loc.fraction)) {
                            Path { path in
                                path.move(to: CGPoint(x: line.x * unitToPoint, y: line.top * unitToPoint))
                                path.addLine(to: CGPoint(x: line.x * unitToPoint, y: line.bottom * unitToPoint))
                            }
                            .stroke(Self.playbackCursor,
                                    style: StrokeStyle(lineWidth: max(line.width * unitToPoint, 2),
                                                       lineCap: .round))
                            .allowsHitTesting(false)
                        }
                    }
                }

                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: contentWidth, height: contentHeight)
                    // A quick tap must fire reliably (add note / select). Nesting the
                    // tap inside an ExclusiveGesture behind a sequenced long-press made
                    // the arbitration swallow single taps, so the two are split:
                    //   - the tap is a standalone highPriorityGesture so it wins over the
                    //     surrounding ScrollView's pan/double-tap;
                    //   - hold-0.3s-then-drag re-pitch is a separate simultaneousGesture
                    //     that only engages after the long-press, so it never competes
                    //     with a quick tap.
                    .highPriorityGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                handleTap(at: value.location, unitToPoint: unitToPoint, geometry: geometry)
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                if case .second(true, let drag?) = value {
                                    handleRepitchDrag(at: drag.location, unitToPoint: unitToPoint, geometry: geometry)
                                }
                            }
                    )
            }
        }
        .frame(width: contentWidth, height: contentHeight)
        // MuseScore 4 paper is a faint off-white (#F9F9F9), not pure white — softer
        // on the eye against the desk behind it.
        .background(Color(hex: "#F9F9F9"))
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 9, x: 0, y: 3)
    }

    /// One tap handler for every mode, matching the classic renderer's contract:
    ///   1. Move the model focus (part/staff/measure) to the tapped position, so an
    ///      add lands under the finger and the caret / "current measure" follow the
    ///      tap even in a wide multi-measure score.
    ///   2. A tap on an existing notehead selects it (toggles) in EVERY mode — you
    ///      can pick a note to edit without leaving note/rest input.
    ///   3. Only a tap on empty staff space acts on the input mode (add note / rest).
    private func handleTap(at location: CGPoint, unitToPoint: CGFloat, geometry: VerovioSVGGeometry) {
        let vb = CGPoint(x: location.x / unitToPoint, y: location.y / unitToPoint)
        let located = geometry.locate(x: vb.x, y: vb.y)
        if let loc = located, let ps = viewModel.partStaff(forFlattenedStaffIndex: loc.staffInMeasure) {
            viewModel.focusStaff(partIndex: ps.part, staffIndex: ps.staff)
            viewModel.selectedMeasureIndex = loc.measureIndex
        }

        let tolerance = (geometry.nearestStaff(toY: vb.y)?.staffSpace ?? 180) * 1.5
        if let id = geometry.note(near: vb, tolerance: tolerance) {
            if selectedExportedID == id {
                viewModel.deselectEvent()
            } else {
                _ = viewModel.selectEvent(byExportedID: id)
            }
            return
        }

        viewModel.deselectEvent()
        switch viewModel.inputMode {
        case .note:
            if let loc = located { addNote(at: vb, staff: loc.staff) }
        case .rest:
            viewModel.addRest()
        case .navigate, .repitch:
            // Re-pitch takes pitch from keyboard/piano only (mouse disabled in
            // MuseScore); a tap just selects which note to re-pitch.
            break
        }
    }

    /// The Verovio exported id of the currently selected event, or nil. Mirrors the
    /// `@xml:id` Verovio drew (`e` + dashless-lowercase UUID), so it matches back to
    /// a rendered notehead for the selection ring.
    private var selectedExportedID: String? {
        guard let event = viewModel.selectedEvent else { return nil }
        return "e" + event.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Every selected event's Verovio id — one for a single selection, many for a
    /// range (MuseScore recolours the whole blue range, not just one glyph).
    private var selectedExportedIDs: [String] {
        viewModel.selectedEventIDs.map {
            "e" + $0.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
    }

    /// The insertion caret band (viewBox units) at the model's current focus — the
    /// translucent blue column marking where an appended note/rest lands, matching
    /// MuseScore's note-input caret. Shown only in the add modes (`.note`/`.rest`) so
    /// navigation stays uncluttered. nil when the focused staff is not on the current
    /// render.
    private func cursorCaret(in geometry: VerovioSVGGeometry)
        -> (x: CGFloat, top: CGFloat, bottom: CGFloat, width: CGFloat)? {
        guard (viewModel.inputMode == .note || viewModel.inputMode == .rest),
              let flat = viewModel.flattenedStaffIndex(part: viewModel.selectedPartIndex,
                                                       staff: viewModel.selectedStaffIndex) else {
            return nil
        }
        // Anchor the caret on the rendered element at the cursor beat (MuseScore's
        // caret rides the drawn note/rest, not a measure-level indent). Fall back to
        // the indent heuristic only if that event was not drawn — e.g. a measure
        // mid-re-render.
        if let id = viewModel.caretExportedID,
           let band = geometry.insertionColumn(forEventID: id) {
            return band
        }
        return geometry.insertionColumn(measureIndex: viewModel.selectedMeasureIndex,
                                        staffInMeasure: flat)
    }

    /// Resolve the tapped vertical position to a pitch — diatonic steps from the
    /// tapped staff's middle line, read through *that staff's* clef — and insert it
    /// at the cursor. The model focus (part/staff/measure) was already moved to the
    /// tapped staff by `handleTap`, so `effectiveClef`/`effectiveKeySignature` read
    /// the right staff: an F tapped on the bass staff in G major comes out F♯, and
    /// an explicit toolbar accidental overrides the key.
    private func addNote(at vb: CGPoint, staff: VerovioSVGGeometry.Staff) {
        guard let steps = geometry?.diatonicStepsAboveMiddle(ofStaff: staff, y: vb.y) else { return }
        let position = viewModel.effectiveClef.referencePitch.staffPosition + steps
        var pitch = Pitch.fromStaffPosition(position)
        let accidental = viewModel.selectedAccidental
            ?? viewModel.effectiveKeySignature.accidental(for: pitch.name)
        if accidental != .natural {
            pitch = Pitch(name: pitch.name, octave: pitch.octave, accidental: accidental)
        }
        viewModel.insertNoteAtCursor(pitch)
    }

    /// Hold-and-drag on the selected note changes its pitch, reading the vertical
    /// position under the finger through the drag-over staff's clef — the classic
    /// renderer's `updateSelectedEventPitch` behaviour. No selection -> no-op, so a
    /// stray long-press on empty staff does nothing.
    private func handleRepitchDrag(at location: CGPoint, unitToPoint: CGFloat, geometry: VerovioSVGGeometry) {
        guard viewModel.selectedEvent != nil else { return }
        let vb = CGPoint(x: location.x / unitToPoint, y: location.y / unitToPoint)
        guard let staff = geometry.nearestStaff(toY: vb.y),
              let steps = geometry.diatonicStepsAboveMiddle(ofStaff: staff, y: vb.y) else { return }
        let position = viewModel.effectiveClef.referencePitch.staffPosition + steps
        var pitch = Pitch.fromStaffPosition(position)
        let accidental = viewModel.selectedAccidental
            ?? viewModel.effectiveKeySignature.accidental(for: pitch.name)
        if accidental != .natural {
            pitch = Pitch(name: pitch.name, octave: pitch.octave, accidental: accidental)
        }
        viewModel.updateSelectedEventPitch(pitch)
    }

    // MARK: - Render pipeline

    private func render() {
        let engine = VerovioEngine.shared
        guard engine.isReady else {
            status = String(localized: "Verovio engine not ready (resources missing).")
            return
        }
        let xml = MusicXMLExporter().export(score: viewModel.score, colorizeVoices: true)
        guard let rendered = engine.renderSVG(fromMusicXML: xml) else {
            // Keep the last good SVG (if any) rather than blanking on a transient miss.
            status = "Verovio returned an empty render (MusicXML \(xml.count) chars)."
            return
        }
        svg = rendered
        geometry = VerovioSVGGeometry.parse(rendered)
        status = geometry == nil
            ? "SVG rendered (\(rendered.count) B) but geometry not parsed — taps disabled."
            : ""
    }
}

/// Minimal, non-zoomable SVG host. Zoom/scroll is handled by the parent so the
/// on-screen geometry stays a fixed uniform scale of the viewBox — that is what
/// keeps tap mapping exact.
private struct SVGWebView: UIViewRepresentable {
    let svg: String
    /// CSS colour for the engraving ("white" on dark UI, "black" on light).
    let ink: String
    /// Verovio ids (`e<hex>`) of every selected note/chord, recoloured in place —
    /// MuseScore recolours the selected glyphs themselves rather than drawing a ring.
    var highlightIDs: [String] = []
    /// Voice colour applied to the selected glyph.
    var highlightColor: String = "#0065BF"

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastSVG: String?
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bouncesZoom = false
        // Display-only: zoom/scroll/taps are all handled by the SwiftUI parent. The
        // WKWebView's own gesture recognizers otherwise swallow taps meant for the
        // transparent tap overlay stacked on top of it, which is what made note
        // input / selection dead. Turning off its interaction lets every tap reach
        // the overlay's gesture.
        webView.isUserInteractionEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload the whole document only when the engraving itself changed. A mere
        // selection change updates the highlight <style> via JS, so picking a note
        // recolours instantly without a full white-flash reload.
        if context.coordinator.lastSVG != svg {
            context.coordinator.lastSVG = svg
            webView.loadHTMLString(Self.html(svg, ink: ink, highlightRule: Self.rule(highlightIDs, highlightColor)), baseURL: nil)
        } else {
            let css = Self.rule(highlightIDs, highlightColor)
            let js = "var s=document.getElementById('hl'); if(s){s.textContent=\(Self.jsString(css));}"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    /// CSS that recolours every selected glyph group (notehead, stem, flags, dots) to
    /// the voice colour. Empty when nothing is selected. `stroke:currentColor` stems
    /// follow the `color` override; noteheads follow `fill`.
    private static func rule(_ ids: [String], _ color: String) -> String {
        let clean = ids.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return "" }
        let selector = clean.flatMap { ["#\($0)", "#\($0) *"] }.joined(separator: ", ")
        return "\(selector) { fill: \(color) !important; color: \(color) !important; stroke: \(color) !important; }"
    }

    private static func jsString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
        return "'\(escaped)'"
    }

    private static func html(_ svg: String, ink: String, highlightRule: String) -> String {
        // Verovio draws staff lines/stems with `stroke:currentColor` and glyphs by
        // inheriting `fill`. On a dark background the default black is invisible, so
        // we set ink (resolved from the SwiftUI colour scheme) as the inherited
        // colour+fill. It is deliberately NOT `!important`: Verovio tints voice 2–4
        // notes with per-note `color`/`fill` presentation attributes, and inheritance
        // must LOSE to those so voice colours survive on screen. Verified: uncolored
        // glyphs render ink, colored notes keep their tint (rsvg cascade check).
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
            html, body { margin: 0; padding: 0; background: transparent; color: \(ink); }
            svg { width: 100% !important; height: auto !important; display: block; }
            svg { color: \(ink); fill: \(ink); }
        </style>
        <style id="hl">\(highlightRule)</style></head>
        <body>\(svg)</body></html>
        """
    }
}
