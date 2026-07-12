import SwiftUI
import WebKit

/// Stage 1 of migrating the editing surface onto the real Verovio engine:
/// the score is *engraved by Verovio* (not our homemade EngravingEngine) and
/// tapping a rendered notehead selects the matching event in our model. This
/// proves the round-trip — model → MusicXML (with ids) → Verovio SVG → tap →
/// geometry → back to the model — end to end, on device.
///
/// It fixes, in the real app, the two layout bugs the homemade engine had
/// (grand-staff staves diverging in height, a lone measure stretched full width),
/// because Verovio lays out by professional rules.
///
/// Not yet the full editor: tap-to-*add* a note comes next; for now an empty tap
/// is a no-op (the working StaffAreaView editor stays the source of truth and is
/// untouched — this screen is reached from a toggle, never replacing it yet).
///
/// Failure modes:
///   - Verovio not ready / rejects the score -> Detect: `render()` yields nil svg or nil geometry
///       -> Recover: show a notice, no crash; user closes and keeps using the native editor.
///   - Tap misses every notehead -> Detect: `note(near:)` == nil
///       -> Recover: treated as a no-op deselect, nothing added or lost.
struct VerovioEditorView: View {
    @ObservedObject var viewModel: ScoreViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var svg: String?
    @State private var geometry: VerovioSVGGeometry?
    @State private var selectedNotePoint: CGPoint?   // in viewBox units
    @State private var statusText: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if let svg, let geometry {
                    GeometryReader { proxy in
                        engravedScore(svg: svg, geometry: geometry, containerWidth: proxy.size.width)
                    }
                } else {
                    ContentUnavailableView(
                        String(localized: "Cannot engrave"),
                        systemImage: "music.note.list",
                        description: Text(String(localized: "Verovio could not render this score."))
                    )
                }
            }
            .navigationTitle(String(localized: "Verovio Staff"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
            }
            .task { render() }
        }
    }

    // MARK: - Engraved score + tap layer

    private func engravedScore(svg: String, geometry: VerovioSVGGeometry, containerWidth: CGFloat) -> some View {
        // The SVG is scaled uniformly to fit the container width; content height
        // follows the intrinsic aspect ratio. One viewBox unit therefore equals
        // `containerWidth / viewBox.width` points on screen — the single factor
        // that maps a tap back to viewBox coordinates and a note back to screen.
        let unitToPoint = containerWidth / geometry.viewBox.width
        let contentHeight = geometry.pixelSize.height * (containerWidth / geometry.pixelSize.width)

        return ScrollView(.vertical) {
            ZStack(alignment: .topLeading) {
                SVGView(svg: svg)
                    .frame(width: containerWidth, height: contentHeight)

                if let p = selectedNotePoint {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: 26, height: 26)
                        .position(x: p.x * unitToPoint, y: p.y * unitToPoint)
                        .allowsHitTesting(false)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: containerWidth, height: contentHeight)
                    .onTapGesture { location in
                        handleTap(at: location, unitToPoint: unitToPoint, geometry: geometry)
                    }
            }
            .frame(width: containerWidth, height: contentHeight)
        }
    }

    private func handleTap(at location: CGPoint, unitToPoint: CGFloat, geometry: VerovioSVGGeometry) {
        let vb = CGPoint(x: location.x / unitToPoint, y: location.y / unitToPoint)
        let tolerance = (geometry.nearestStaff(toY: vb.y)?.staffSpace ?? 180) * 1.5
        guard let id = geometry.note(near: vb, tolerance: tolerance),
              let note = geometry.notes.first(where: { $0.id == id }) else {
            statusText = String(localized: "Tapped empty staff")
            return
        }
        if viewModel.selectEvent(byExportedID: id) {
            selectedNotePoint = note.point
            statusText = pitchDescription() ?? String(localized: "Note selected")
        } else {
            statusText = String(localized: "Note not found in model")
        }
    }

    private func pitchDescription() -> String? {
        guard let event = viewModel.selectedEvent else { return nil }
        switch event.type {
        case .note(let p): return "\(p.name.englishName)\(p.octave)"
        case .chord(let ps): return ps.map { "\($0.name.englishName)\($0.octave)" }.joined(separator: "+")
        case .rest: return String(localized: "Rest")
        }
    }

    // MARK: - Render pipeline

    private func render() {
        let engine = VerovioEngine.shared
        guard engine.isReady else { svg = nil; geometry = nil; return }
        let xml = MusicXMLExporter().export(score: viewModel.score)
        guard let rendered = engine.renderSVG(fromMusicXML: xml) else {
            svg = nil; geometry = nil; return
        }
        svg = rendered
        geometry = VerovioSVGGeometry.parse(rendered)
        statusText = geometry.map { String(localized: "Tap a note to select · \($0.notes.count) notes") } ?? ""
    }
}

/// Minimal, non-zoomable SVG host. Zoom/scroll is disabled so the on-screen
/// geometry stays a fixed uniform scale of the viewBox — that is what keeps tap
/// mapping exact. Vertical scrolling is handled by the enclosing SwiftUI ScrollView.
private struct SVGView: UIViewRepresentable {
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
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
            html, body { margin: 0; padding: 0; background: transparent; }
            svg { width: 100% !important; height: auto !important; display: block; }
        </style></head>
        <body>\(svg)</body></html>
        """
    }
}
