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
    /// Width measured by the parent outside the ScrollView (a GeometryReader
    /// nested in a ScrollView collapses to zero height).
    let availableWidth: CGFloat

    /// MuseScore 4 voice-1 / selection blue (#0065BF), from engravingconfiguration.cpp.
    /// Used for the input caret and selection ring so they match the reference editor
    /// instead of the theme-dependent system accent.
    private static let museScoreSelectionBlue = Color(hex: "#0065BF")

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
            SVGWebView(svg: svg, ink: "black")
                .frame(width: contentWidth, height: contentHeight)

            if let geometry {
                if let caret = cursorCaret(in: geometry) {
                    Path { path in
                        path.move(to: CGPoint(x: caret.x * unitToPoint, y: caret.top * unitToPoint))
                        path.addLine(to: CGPoint(x: caret.x * unitToPoint, y: caret.bottom * unitToPoint))
                    }
                    // MuseScore 4 voice-1 / note-input caret colour (#0065BF), not the
                    // system accent — the theme-dependent iOS blue read as an artefact.
                    .stroke(Self.museScoreSelectionBlue.opacity(0.8), lineWidth: 1.5)
                    .allowsHitTesting(false)
                }

                if let p = selectedNotePoint(in: geometry) {
                    Circle()
                        .stroke(Self.museScoreSelectionBlue, lineWidth: 2)
                        .frame(width: 26, height: 26)
                        .position(x: p.x * unitToPoint, y: p.y * unitToPoint)
                        .allowsHitTesting(false)
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

    /// Screen-independent (viewBox-unit) centre of the selected note's notehead, or
    /// nil if nothing is selected / the note is not on the current render. Derived
    /// each layout from the model + geometry rather than stored, so it stays correct
    /// after the score is edited and re-engraved.
    private func selectedNotePoint(in geometry: VerovioSVGGeometry) -> CGPoint? {
        guard let base = selectedExportedID else { return nil }
        return geometry.notes.first(where: { $0.id == base || $0.id.hasPrefix(base + "-") })?.point
    }

    /// The insertion caret (viewBox units) at the model's current focus — the
    /// vertical line marking where an appended note/rest lands. Shown only in the
    /// add modes (`.note`/`.rest`) so navigation stays uncluttered; the ends run
    /// half a staff-space past the top/bottom lines so the caret reads clearly.
    /// nil when the focused staff is not on the current render.
    private func cursorCaret(in geometry: VerovioSVGGeometry) -> (x: CGFloat, top: CGFloat, bottom: CGFloat)? {
        guard (viewModel.inputMode == .note || viewModel.inputMode == .rest),
              let flat = viewModel.flattenedStaffIndex(part: viewModel.selectedPartIndex,
                                                       staff: viewModel.selectedStaffIndex),
              let hit = geometry.insertionPoint(measureIndex: viewModel.selectedMeasureIndex,
                                                staffInMeasure: flat) else {
            return nil
        }
        let overshoot = hit.staff.staffSpace * 0.5
        return (hit.x, hit.staff.top - overshoot, hit.staff.bottom + overshoot)
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
        webView.loadHTMLString(Self.html(svg, ink: ink), baseURL: nil)
    }

    private static func html(_ svg: String, ink: String) -> String {
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
        </style></head>
        <body>\(svg)</body></html>
        """
    }
}
