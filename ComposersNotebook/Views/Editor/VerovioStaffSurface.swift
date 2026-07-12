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

    @State private var svg: String?
    @State private var geometry: VerovioSVGGeometry?
    @State private var selectedNotePoint: CGPoint?   // viewBox units
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

        return ZStack(alignment: .topLeading) {
            SVGWebView(svg: svg)
                .frame(width: contentWidth, height: contentHeight)

            if let p = selectedNotePoint {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .position(x: p.x * unitToPoint, y: p.y * unitToPoint)
                    .allowsHitTesting(false)
            }

            if let geometry {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: contentWidth, height: contentHeight)
                    .onTapGesture { location in
                        handleTap(at: location, unitToPoint: unitToPoint, geometry: geometry)
                    }
            }
        }
        .frame(width: contentWidth, height: contentHeight)
    }

    private func handleTap(at location: CGPoint, unitToPoint: CGFloat, geometry: VerovioSVGGeometry) {
        let vb = CGPoint(x: location.x / unitToPoint, y: location.y / unitToPoint)
        switch viewModel.inputMode {
        case .note: addNote(at: vb, geometry: geometry)
        case .rest: viewModel.addRest()
        case .navigate: selectNote(at: vb, geometry: geometry)
        }
    }

    private func selectNote(at vb: CGPoint, geometry: VerovioSVGGeometry) {
        let tolerance = (geometry.nearestStaff(toY: vb.y)?.staffSpace ?? 180) * 1.5
        guard let id = geometry.note(near: vb, tolerance: tolerance),
              let note = geometry.notes.first(where: { $0.id == id }),
              viewModel.selectEvent(byExportedID: id) else {
            selectedNotePoint = nil
            return
        }
        selectedNotePoint = note.point
    }

    /// Resolve the tapped vertical position to a pitch — steps from the nearest
    /// staff's middle line, read through the current clef — and insert it at the
    /// cursor. Pitch comes from Y; the note lands at the model cursor.
    private func addNote(at vb: CGPoint, geometry: VerovioSVGGeometry) {
        guard let staff = geometry.nearestStaff(toY: vb.y),
              let steps = geometry.diatonicStepsAboveMiddle(ofStaff: staff, y: vb.y) else {
            return
        }
        let position = viewModel.effectiveClef.referencePitch.staffPosition + steps
        viewModel.insertNoteAtCursor(Pitch.fromStaffPosition(position))
        selectedNotePoint = nil
    }

    // MARK: - Render pipeline

    private func render() {
        let engine = VerovioEngine.shared
        guard engine.isReady else {
            status = String(localized: "Verovio engine not ready (resources missing).")
            return
        }
        let xml = MusicXMLExporter().export(score: viewModel.score)
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

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bouncesZoom = false
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(Self.html(svg), baseURL: nil)
    }

    private static func html(_ svg: String) -> String {
        // Verovio draws staff lines with `stroke:currentColor` and glyphs with a
        // default (black) fill. On a dark background black is invisible, so we
        // drive both from `color`, which follows the system light/dark scheme —
        // the engraving is black on light, white on dark, like the rest of the UI.
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
            html, body { margin: 0; padding: 0; background: transparent; color: black; }
            @media (prefers-color-scheme: dark) { html, body { color: white; } }
            svg { width: 100% !important; height: auto !important; display: block; }
            svg, svg * { fill: currentColor; }
        </style></head>
        <body>\(svg)</body></html>
        """
    }
}
