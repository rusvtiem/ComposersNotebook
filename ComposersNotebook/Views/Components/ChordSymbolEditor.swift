import SwiftUI

// MARK: - Chord Symbol Editor
//
// Sheet для ввода аккордового символа через свободный текст ("Am7", "G/B")
// либо через структурный пикер (root + quality + bass).
// Парсинг через ChordSymbol.parse(_:).

struct ChordSymbolEditor: View {
    @ObservedObject var viewModel: ScoreViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var textInput: String = ""
    @State private var parseError: Bool = false

    private var existingSymbol: ChordSymbol? {
        viewModel.selectedEvent?.chordSymbol
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Chord Symbol")) {
                    TextField("Am7 / G/B / C#maj7", text: $textInput)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit { applyText() }

                    if parseError {
                        Text(String(localized: "Could not parse chord symbol. Examples: C, Am, G7, Cmaj7, C/E"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section(String(localized: "Quick presets")) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()), GridItem(.flexible()),
                        GridItem(.flexible()), GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(commonPresets, id: \.self) { preset in
                            Button(preset) {
                                textInput = preset
                                applyText()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if existingSymbol != nil {
                    Section {
                        Button(role: .destructive) {
                            viewModel.setChordSymbolForSelectedEvent(nil)
                            HapticManager.success()
                            dismiss()
                        } label: {
                            Label(String(localized: "Remove chord symbol"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Chord Symbol"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Apply")) { applyText() }
                        .disabled(textInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                textInput = existingSymbol?.displayText ?? ""
            }
        }
    }

    private let commonPresets: [String] = [
        "C", "G", "D", "A",
        "Am", "Em", "Dm", "Bm",
        "G7", "D7", "A7", "E7",
        "Cmaj7", "Am7", "Dm7", "G7",
        "F", "Bb", "C/E", "G/B"
    ]

    private func applyText() {
        guard let symbol = ChordSymbol.parse(textInput) else {
            parseError = true
            HapticManager.error()
            return
        }
        parseError = false
        viewModel.setChordSymbolForSelectedEvent(symbol)
        HapticManager.success()
        dismiss()
    }
}
