import SwiftUI

// MARK: - Validation View
//
// Открывается из меню "..." → "Validate Score". Прогоняет
// ScoreValidator (см. Слой 1) и показывает список проблем
// сгруппированный по серьёзности.
//
// При тапе на проблему — переходим на соответствующий такт/ноту
// в редакторе (выбираем их через viewModel).

struct ValidationView: View {
    @ObservedObject var viewModel: ScoreViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var issues: [ScoreValidator.Issue] = []

    private var counts: (errors: Int, warnings: Int, info: Int) {
        ScoreValidator.counts(issues)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Score Validation"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            runValidation()
                        } label: {
                            Label(String(localized: "Re-check"), systemImage: "arrow.clockwise")
                        }
                    }
                }
                .onAppear { runValidation() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if issues.isEmpty {
            ContentUnavailableView(
                String(localized: "No issues found"),
                systemImage: "checkmark.seal.fill",
                description: Text(String(localized: "The score passes all built-in checks: instrument ranges, measure timing, voice conflicts, and playback techniques."))
            )
        } else {
            List {
                Section {
                    summaryBar
                }

                let errors = issues.filter { $0.severity == .error }
                let warnings = issues.filter { $0.severity == .warning }
                let infos = issues.filter { $0.severity == .info }

                if !errors.isEmpty {
                    Section(header: severityHeader(label: String(localized: "Errors"), color: .red, count: errors.count)) {
                        ForEach(errors) { issue in
                            IssueRow(issue: issue) { jump(to: issue) }
                        }
                    }
                }
                if !warnings.isEmpty {
                    Section(header: severityHeader(label: String(localized: "Warnings"), color: .orange, count: warnings.count)) {
                        ForEach(warnings) { issue in
                            IssueRow(issue: issue) { jump(to: issue) }
                        }
                    }
                }
                if !infos.isEmpty {
                    Section(header: severityHeader(label: String(localized: "Notes"), color: .blue, count: infos.count)) {
                        ForEach(infos) { issue in
                            IssueRow(issue: issue) { jump(to: issue) }
                        }
                    }
                }
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 16) {
            summaryChip(count: counts.errors, color: .red, label: String(localized: "Errors"))
            summaryChip(count: counts.warnings, color: .orange, label: String(localized: "Warnings"))
            summaryChip(count: counts.info, color: .blue, label: String(localized: "Notes"))
            Spacer()
        }
    }

    private func summaryChip(count: Int, color: Color, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func severityHeader(label: String, color: Color, count: Int) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
            Text("(\(count))")
                .foregroundStyle(.secondary)
        }
    }

    private func runValidation() {
        issues = ScoreValidator.validate(viewModel.score)
        HapticManager.buttonTap()
    }

    @MainActor
    private func jump(to issue: ScoreValidator.Issue) {
        viewModel.selectPart(at: issue.partIndex)
        viewModel.selectedMeasureIndex = issue.measureIndex
        if let ei = issue.eventIndex {
            viewModel.selectEvent(at: ei)
        } else {
            viewModel.deselectEvent()
        }
        HapticManager.success()
        dismiss()
    }
}

// MARK: - Issue row

private struct IssueRow: View {
    let issue: ScoreValidator.Issue
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.message)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(locationString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch issue.severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch issue.severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private var locationString: String {
        let partStr = String(format: NSLocalizedString("Part %d", comment: ""), issue.partIndex + 1)
        let measureStr = String(format: NSLocalizedString("measure %d", comment: ""), issue.measureIndex + 1)
        if let ei = issue.eventIndex {
            let noteStr = String(format: NSLocalizedString("note %d", comment: ""), ei + 1)
            return "\(partStr), \(measureStr), \(noteStr)"
        } else {
            return "\(partStr), \(measureStr)"
        }
    }
}
