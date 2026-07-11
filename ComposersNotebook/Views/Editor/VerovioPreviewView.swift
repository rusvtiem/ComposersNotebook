import SwiftUI
import WebKit

/// Read-only, high-fidelity preview of the current score rendered by the real
/// Verovio engraving engine (RISM Digital). The Canvas editor stays the source
/// of truth for input; this view only *shows* how a professional engine lays
/// out whole systems and aligns a grand staff — the thing our homemade
/// EngravingEngine could not do (staves diverging in height, measures stretched).
///
/// Pipeline: current Score -> MusicXMLExporter -> Verovio -> SVG -> WKWebView.
///
/// Failure modes:
///   - Engine not ready (resource bundle missing) -> Detect: `VerovioEngine.isReady == false`
///       -> Recover: show explanatory notice, no crash, editor unaffected.
///   - render returns nil (Verovio rejects the MusicXML) -> Detect: `svg == nil`
///       -> Recover: show explanatory notice; user stays on the native editor.
struct VerovioPreviewView: View {
    let score: Score
    @Environment(\.dismiss) private var dismiss

    @State private var state: RenderState = .rendering

    enum RenderState: Equatable {
        case rendering
        case ok(String)   // svg
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .rendering:
                    ProgressView(String(localized: "Engraving with Verovio…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ok(let svg):
                    SVGWebView(svg: svg)
                        .ignoresSafeArea(edges: .bottom)
                case .failed(let message):
                    ContentUnavailableView(
                        String(localized: "Preview unavailable"),
                        systemImage: "music.note.list",
                        description: Text(message)
                    )
                }
            }
            .navigationTitle(String(localized: "Verovio Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if VerovioEngine.shared.isReady {
                        Text("Verovio \(VerovioEngine.shared.version)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task { render() }
        }
    }

    private func render() {
        let engine = VerovioEngine.shared
        guard engine.isReady else {
            state = .failed(String(localized: "Verovio engine is not ready (resources missing)."))
            return
        }
        let xml = MusicXMLExporter().export(score: score)
        if let svg = engine.renderSVG(fromMusicXML: xml) {
            state = .ok(svg)
        } else {
            state = .failed(String(localized: "Verovio could not render this score."))
        }
    }
}

/// Displays a Verovio SVG string inside a pinch-zoomable WKWebView.
/// The SVG is width-fitted via CSS (`!important` beats Verovio's fixed px
/// width/height attributes) while `viewBox` preserves the aspect ratio.
private struct SVGWebView: UIViewRepresentable {
    let svg: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.scrollView.minimumZoomScale = 0.5
        webView.scrollView.maximumZoomScale = 5.0
        webView.scrollView.bouncesZoom = true
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
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5, user-scalable=yes">
        <style>
            html, body { margin: 0; padding: 8px; background: transparent; }
            svg { width: 100% !important; height: auto !important; display: block; }
        </style>
        </head>
        <body>\(svg)</body>
        </html>
        """
    }
}
