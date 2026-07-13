import Foundation
import VerovioToolkit

/// Wraps the Verovio engraving engine (C++ via Swift binding).
/// Renders MusicXML to SVG. The engine lays out whole systems and aligns
/// staves across measures — this is what our homemade layout could not do
/// without collapsing on input (bugs #2/#7).
///
/// Failure modes:
///   - Resource bundle missing            -> Detect: `data` url == nil -> Recover: `isReady == false`, render() returns nil, UI falls back to native Canvas.
///   - loadData rejects the MusicXML      -> Detect: loadData returns false -> Recover: render() returns nil, caller keeps last good SVG.
///   - renderToSVG returns empty string   -> Detect: svg.isEmpty -> Recover: render() returns nil, caller keeps last good SVG.
final class VerovioEngine {
    static let shared = VerovioEngine()

    private let toolkit = VerovioToolkit()
    private(set) var isReady = false

    private init() {
        guard let dataURL = VerovioResources.bundle.url(forResource: "data", withExtension: nil) else {
            return
        }
        isReady = toolkit.setResourcePath(dataURL.path)
    }

    /// Options mirror the validated spike: A4 page, auto page height, scale 40,
    /// automatic system breaks, no header/footer chrome.
    /// `font: Bravura` — the SMuFL reference font (Steinberg), same glyph set the
    /// professional engravers use; without it Verovio falls back to Leipzig.
    /// staffLineWidth/stemWidth left at Verovio defaults so it honours Bravura's
    /// own engravingDefaults.
    private static let options = """
    {"pageWidth": 2100, "pageHeight": 2970, "adjustPageHeight": true, "scale": 40, "breaks": "auto", "header": "none", "footer": "none", "font": "Bravura"}
    """

    /// Render a full MusicXML document to a single SVG (page 1).
    /// Returns nil on any failure so the caller can keep the previous render.
    func renderSVG(fromMusicXML xml: String) -> String? {
        guard isReady else { return nil }
        _ = toolkit.setOptions(Self.options)
        guard toolkit.loadData(xml) else { return nil }
        let svg = toolkit.renderToSVG(1, true)
        return svg.isEmpty ? nil : svg
    }

    var version: String { toolkit.getVersion() }
}
