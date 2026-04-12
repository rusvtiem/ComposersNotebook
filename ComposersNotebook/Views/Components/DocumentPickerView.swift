import SwiftUI
import UniformTypeIdentifiers

// MARK: - Document Picker for Import

struct DocumentPickerView: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Supported Import Types

extension UTType {
    static let musicXML = UTType(filenameExtension: "musicxml") ?? .xml
    static let mxl = UTType(filenameExtension: "mxl") ?? .data
    static let midiFile = UTType(filenameExtension: "mid") ?? .midi
    static let guitarPro = UTType(filenameExtension: "gp") ?? .data
    static let guitarPro5 = UTType(filenameExtension: "gp5") ?? .data
    static let guitarProX = UTType(filenameExtension: "gpx") ?? .data
    static let abcNotation = UTType(filenameExtension: "abc") ?? .plainText
    static let mei = UTType(filenameExtension: "mei") ?? .xml
    static let capella = UTType(filenameExtension: "capx") ?? .data
}
