import SwiftUI
import UniformTypeIdentifiers

// MARK: - SoundFont Picker View
//
// Главное меню SoundFont:
//  - Встроенные (built-in) — нельзя удалить.
//  - Скачанные (downloaded) — скачаны из приложения, можно удалить.
//  - Доступны для скачивания (recommended) — список с homepage / автором /
//    лицензией / размером. Если directDownloadURL nil → кнопка "Open author
//    site" + инструкция. Если есть — кнопка "Download" со прогрессом.
//  - Импортированные пользователем (userImported) — через "+" → Files picker.
//
// При недоступности всех зеркал (или отсутствии directDownloadURL) пользователь
// получает плашку с кнопкой на сайт автора и инструкцией ручного импорта.

struct SoundFontPickerView: View {
    @ObservedObject var soundFontManager: SoundFontManager
    @Environment(\.dismiss) private var dismiss

    @State private var showImportPicker = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var openAuthorSiteFor: SoundFontManager.RecommendedSoundFont?

    var body: some View {
        NavigationStack {
            List {
                infoSection

                builtInSection

                if !downloadedFonts.isEmpty {
                    downloadedSection
                }

                availableForDownloadSection

                if !userImportedFonts.isEmpty {
                    userImportedSection
                }

                importButtonSection
            }
            .navigationTitle(String(localized: "SoundFont"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showImportPicker) {
                DocumentPickerView(
                    contentTypes: [UTType(filenameExtension: "sf2") ?? .data],
                    onPick: { url in tryImport(url) }
                )
            }
            .alert(String(localized: "Import error"), isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .sheet(item: $openAuthorSiteFor) { rec in
                AuthorSiteSheet(recommended: rec)
            }
        }
    }

    // MARK: - Sections

    private var infoSection: some View {
        Section {
            Text(String(localized: "Choose which SoundFont to use for playback. Built-in fonts come with the app; you can download more from the recommended list or import your own .sf2 file."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var builtInSection: some View {
        Section(String(localized: "SoundFonts (built-in)")) {
            ForEach(builtInFonts) { font in
                FontRow(
                    font: font,
                    isActive: soundFontManager.activeSoundFont?.id == font.id,
                    canDelete: false,
                    onSelect: { activate(font) },
                    onDelete: {}
                )
            }
            if builtInFonts.isEmpty {
                Text(String(localized: "No built-in SoundFonts found in the app bundle."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var downloadedSection: some View {
        Section(String(localized: "Downloaded")) {
            ForEach(downloadedFonts) { font in
                FontRow(
                    font: font,
                    isActive: soundFontManager.activeSoundFont?.id == font.id,
                    canDelete: true,
                    onSelect: { activate(font) },
                    onDelete: {
                        try? soundFontManager.deleteDownloadedSoundFont(font)
                        HapticManager.buttonTap()
                    }
                )
            }
        }
    }

    private var availableForDownloadSection: some View {
        Section(String(localized: "Available for download")) {
            ForEach(SoundFontManager.recommendedSoundFonts) { rec in
                recommendedRow(rec)
            }
        }
    }

    private var userImportedSection: some View {
        Section(String(localized: "My imported")) {
            ForEach(userImportedFonts) { font in
                FontRow(
                    font: font,
                    isActive: soundFontManager.activeSoundFont?.id == font.id,
                    canDelete: true,
                    onSelect: { activate(font) },
                    onDelete: {
                        try? soundFontManager.deleteUserSoundFont(font)
                        HapticManager.buttonTap()
                    }
                )
            }
        }
    }

    private var importButtonSection: some View {
        Section {
            Button {
                showImportPicker = true
            } label: {
                Label(String(localized: "Import my own .sf2 file"), systemImage: "plus.circle")
            }
            Text(String(localized: "Pick a .sf2 file from Files. The app validates it and copies into its own storage."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Recommended row

    @ViewBuilder
    private func recommendedRow(_ rec: SoundFontManager.RecommendedSoundFont) -> some View {
        let isDownloaded = soundFontManager.downloadedSoundFontExists(named: rec.fileName)
        let progress = soundFontManager.downloadProgress[rec.id]
        let errorMessage = soundFontManager.downloadErrors[rec.id]

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.name).font(.headline)
                    Text(rec.author).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(rec.estimatedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(rec.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(String(localized: "License")): \(rec.license)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let progress = progress {
                ProgressView(value: progress, total: 1) {
                    Text(String(format: NSLocalizedString("Downloading... %d%%", comment: ""), Int(progress * 100)))
                        .font(.caption)
                }
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button {
                        openAuthorSiteFor = rec
                    } label: {
                        Label(String(localized: "Open author site"), systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }
            } else if isDownloaded {
                Label(String(localized: "Downloaded"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                HStack {
                    if rec.directDownloadURL != nil {
                        Button {
                            soundFontManager.downloadRecommended(rec)
                            HapticManager.buttonTap()
                        } label: {
                            Label(String(localized: "Download"), systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                    Button {
                        openAuthorSiteFor = rec
                    } label: {
                        Label(String(localized: "Open author site"), systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }
                if rec.directDownloadURL == nil {
                    Text(String(localized: "This font has no auto-download. Open the author site, download the .sf2 manually, then import via the button below."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Filtered lists

    private var builtInFonts: [SoundFontManager.SoundFontInfo] {
        soundFontManager.availableSoundFonts.filter { $0.source == .builtIn }
    }

    private var downloadedFonts: [SoundFontManager.SoundFontInfo] {
        soundFontManager.availableSoundFonts.filter { $0.source == .downloaded }
    }

    private var userImportedFonts: [SoundFontManager.SoundFontInfo] {
        soundFontManager.availableSoundFonts.filter { $0.source == .userImported }
    }

    private func activate(_ font: SoundFontManager.SoundFontInfo) {
        soundFontManager.setActiveSoundFont(font)
        HapticManager.success()
    }

    private func tryImport(_ url: URL) {
        do {
            let info = try soundFontManager.importSoundFont(from: url)
            soundFontManager.setActiveSoundFont(info)
            HapticManager.success()
        } catch {
            importError = error.localizedDescription
            showImportError = true
            HapticManager.error()
        }
    }
}

// MARK: - Font row

private struct FontRow: View {
    let font: SoundFontManager.SoundFontInfo
    let isActive: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(font.name)
                        .foregroundStyle(.primary)
                    Text(font.fileSizeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label(String(localized: "Delete"), systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Author site sheet

private struct AuthorSiteSheet: View, Identifiable {
    let recommended: SoundFontManager.RecommendedSoundFont
    var id: String { recommended.id }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(recommended.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(recommended.author)
                    .foregroundStyle(.secondary)

                Divider()

                Text(String(localized: "How to install manually:"))
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("1. " + String(localized: "Tap «Open in Safari» below."))
                    Text("2. " + String(localized: "Find the download link on the author site (usually a .zip)."))
                    Text("3. " + String(localized: "Save to Files."))
                    Text("4. " + String(localized: "If it's a .zip — extract it (long-press → Uncompress)."))
                    Text("5. " + String(localized: "Return to Composer's Notebook → SoundFont menu → \"Import my own .sf2 file\"."))
                }
                .font(.callout)

                Spacer()

                if let url = URL(string: recommended.homepage) {
                    Link(destination: url) {
                        Label(String(localized: "Open in Safari"), systemImage: "safari")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
            .navigationTitle(String(localized: "Manual install"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
    }
}
