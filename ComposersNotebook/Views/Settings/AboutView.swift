import SwiftUI

// MARK: - About View (root)

/// Главный экран "О приложении": версия + подразделы (Лицензии, Связь с автором).
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    appHeader
                        .listRowBackground(Color.clear)
                        .frame(maxWidth: .infinity)
                }

                Section(String(localized: "Information")) {
                    NavigationLink {
                        LicensesView()
                    } label: {
                        Label(String(localized: "Licenses"), systemImage: "doc.text")
                    }

                    NavigationLink {
                        SupportView()
                    } label: {
                        Label(String(localized: "Contact developer"), systemImage: "envelope")
                    }
                }

                if let website = AppSupportContacts.website, !website.isEmpty,
                   let url = URL(string: website) {
                    Section(String(localized: "Links")) {
                        Link(destination: url) {
                            Label(String(localized: "Website"), systemImage: "safari")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "About app"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }

    private var appHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)
                .padding(.top, 8)

            Text("Composer's Notebook")
                .font(.title2)
                .fontWeight(.semibold)

            Text(appVersionString)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    private var appVersionString: String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(String(localized: "Version")) \(version) (\(build))"
    }
}

// MARK: - Licenses View

/// Подэкран с лицензиями всех встраиваемых ресурсов.
///
/// Показывает все ресурсы, которые приложение может предложить — как уже встроенные
/// в bundle, так и доступные для скачивания. Это требование лицензий CC BY / MIT —
/// attribution автора обязательно, независимо от того, активирован ли ресурс прямо сейчас.
struct LicensesView: View {
    var body: some View {
        List {
            Section {
                Text(String(localized: "This app uses third-party resources distributed under open licenses. Authors and license terms are listed below."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "SoundFonts (built-in)")) {
                ForEach(LicenseEntry.builtInSoundFonts) { entry in
                    LicenseRow(entry: entry)
                }
            }

            Section(String(localized: "SoundFonts (available for download)")) {
                ForEach(LicenseEntry.downloadableSoundFonts) { entry in
                    LicenseRow(entry: entry)
                }
            }

            Section(String(localized: "Fonts")) {
                ForEach(LicenseEntry.fonts) { entry in
                    LicenseRow(entry: entry)
                }
            }
        }
        .navigationTitle(String(localized: "Licenses"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - License entry model

/// Метаданные лицензии встраиваемого ресурса.
struct LicenseEntry: Identifiable {
    let id = UUID()
    let resourceName: String
    let author: String
    let license: String
    let websiteURL: URL?
    let description: String

    static let builtInSoundFonts: [LicenseEntry] = [
        LicenseEntry(
            resourceName: "TimGM6mb",
            author: "Tim Brechbill",
            license: "GPL-compatible",
            websiteURL: nil,
            description: String(localized: "Compact General MIDI SoundFont (~6 MB), historical default of the app.")
        )
        // FluidR3 GM добавится сюда после встраивания в bundle (Слой 2, пункт 6).
        // GPL-compatible attribution TimGM6mb остаётся пока он не убран из Resources/.
    ]

    static let downloadableSoundFonts: [LicenseEntry] = [
        LicenseEntry(
            resourceName: "FluidR3 GM",
            author: "Frank Wen",
            license: "MIT",
            websiteURL: URL(string: "https://member.keymusician.com/Member/FluidR3_GM/index.html"),
            description: String(localized: "Stable open-source GM SoundFont (~141 MB).")
        ),
        LicenseEntry(
            resourceName: "GeneralUser GS",
            author: "S. Christian Collins",
            license: "CC BY 3.0",
            websiteURL: URL(string: "https://schristiancollins.com/generaluser.php"),
            description: String(localized: "Compact universal GM SoundFont (~30 MB).")
        ),
        LicenseEntry(
            resourceName: "MuseScore_General",
            author: "MuseScore Studio",
            license: "CC BY 4.0",
            websiteURL: URL(string: "https://musescore.org/en/handbook/4/soundfonts-and-sfz-files"),
            description: String(localized: "Default SoundFont used in MuseScore 4 (~208 MB).")
        ),
        LicenseEntry(
            resourceName: "Sonatina Symphonic Orchestra",
            author: "Mattias Westlund",
            license: "CC Sampling Plus 1.0",
            websiteURL: URL(string: "https://sso.mattiaswestlund.net"),
            description: String(localized: "Orchestral SoundFont (~530 MB).")
        ),
        LicenseEntry(
            resourceName: "Salamander Grand Piano V3",
            author: "Alexander Holm",
            license: "CC BY 3.0",
            websiteURL: URL(string: "https://sfzinstruments.github.io/pianos/salamander/"),
            description: String(localized: "Concert grand piano sampled from Yamaha C5 (~350 MB).")
        )
    ]

    static let fonts: [LicenseEntry] = [
        LicenseEntry(
            resourceName: "Leland",
            author: "Martin Keary, Simon Smith (MuseScore)",
            license: "SIL Open Font License 1.1",
            websiteURL: URL(string: "https://github.com/MuseScoreFonts/Leland"),
            description: String(localized: "Primary SMuFL music notation font.")
        ),
        LicenseEntry(
            resourceName: "Bravura",
            author: "Steinberg Media Technologies",
            license: "SIL Open Font License 1.1",
            websiteURL: URL(string: "https://github.com/steinbergmedia/bravura"),
            description: String(localized: "SMuFL fallback music notation font.")
        )
    ]
}

// MARK: - License row

private struct LicenseRow: View {
    let entry: LicenseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.resourceName)
                    .font(.headline)
                Spacer()
                Text(entry.license)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
            }

            Text(entry.author)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(entry.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let url = entry.websiteURL {
                Link(destination: url) {
                    Label(String(localized: "Source"), systemImage: "link")
                        .font(.caption)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Support View

/// Подэкран связи с автором. Email + Telegram, оба видны всегда.
/// Если контакт не настроен (placeholder пустой) — кнопка остаётся видна,
/// при тапе показывается предупреждение.
struct SupportView: View {
    @State private var showEmailNotConfigured = false
    @State private var showTelegramNotConfigured = false
    @State private var emailOpenFailed = false

    var body: some View {
        List {
            Section {
                Text(String(localized: "If you have a question, suggestion, or want to report an issue, please contact the developer."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "Contact developer")) {
                emailButton
                telegramButton
            }

            Section {
                Text(String(localized: "When writing, please mention your iPhone model and iOS version. A short description of what you were doing when the issue happened helps a lot."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(String(localized: "Contact developer"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "Email is not configured yet"), isPresented: $showEmailNotConfigured) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "The developer hasn't set up an email address yet. Please try writing via Telegram, or check back after an update."))
        }
        .alert(String(localized: "Telegram is not configured yet"), isPresented: $showTelegramNotConfigured) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "The developer hasn't set up a Telegram account yet. Please try writing via email, or check back after an update."))
        }
        .alert(String(localized: "Could not open email app"), isPresented: $emailOpenFailed) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "No email app is configured on this device. Set up Mail (or another email app) in Settings, then try again."))
        }
    }

    private var emailButton: some View {
        Button {
            tapEmail()
        } label: {
            Label(String(localized: "Write an email"), systemImage: "envelope.fill")
        }
    }

    private var telegramButton: some View {
        Button {
            tapTelegram()
        } label: {
            Label(String(localized: "Write on Telegram"), systemImage: "paperplane.fill")
        }
    }

    @MainActor
    private func tapEmail() {
        HapticManager.buttonTap()

        guard AppSupportContacts.isEmailConfigured else {
            showEmailNotConfigured = true
            return
        }

        let subject = String(localized: "Composer's Notebook — question")
        let body = "\n\n\(AppSupportContacts.deviceDiagnosticsString())"

        guard let url = AppSupportContacts.makeMailURL(subject: subject, body: body) else {
            emailOpenFailed = true
            return
        }

        guard UIApplication.shared.canOpenURL(url) else {
            emailOpenFailed = true
            return
        }

        UIApplication.shared.open(url)
    }

    @MainActor
    private func tapTelegram() {
        HapticManager.buttonTap()

        guard AppSupportContacts.isTelegramConfigured,
              let url = AppSupportContacts.makeTelegramURL() else {
            showTelegramNotConfigured = true
            return
        }

        UIApplication.shared.open(url)
    }
}
