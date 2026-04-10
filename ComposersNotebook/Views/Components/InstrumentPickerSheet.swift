import SwiftUI

struct InstrumentPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    let onSelect: (Instrument) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(InstrumentGroup.allCases, id: \.self) { group in
                    Section(group.displayName) {
                        ForEach(Instrument.instruments(for: group)) { instrument in
                            Button {
                                onSelect(instrument)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(instrument.name)
                                            .font(.body)
                                        Text(instrument.rangeDisplayString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(instrument.shortName)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "Add Instrument"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
    }
}
