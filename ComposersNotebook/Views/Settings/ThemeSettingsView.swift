import SwiftUI

struct ThemeSettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var showCustomThemeEditor = false
    @State private var editingTheme: AppTheme?

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Встроенные темы")) {
                    ForEach(AppTheme.allBuiltIn) { theme in
                        ThemeRow(theme: theme, isSelected: themeManager.currentTheme.id == theme.id) {
                            themeManager.applyTheme(theme)
                            HapticManager.buttonTap()
                        }
                    }
                }

                if !themeManager.customThemes.isEmpty {
                    Section(String(localized: "Пользовательские")) {
                        ForEach(themeManager.customThemes) { theme in
                            ThemeRow(theme: theme, isSelected: themeManager.currentTheme.id == theme.id) {
                                themeManager.applyTheme(theme)
                                HapticManager.buttonTap()
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    themeManager.deleteCustomTheme(id: theme.id)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                                Button {
                                    editingTheme = theme
                                    showCustomThemeEditor = true
                                } label: {
                                    Label("Изменить", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        let base = themeManager.currentTheme
                        editingTheme = AppTheme(
                            id: UUID().uuidString,
                            name: "Моя тема",
                            isBuiltIn: false,
                            accentHex: base.accentHex,
                            backgroundHex: base.backgroundHex,
                            surfaceHex: base.surfaceHex,
                            textPrimaryHex: base.textPrimaryHex,
                            textSecondaryHex: base.textSecondaryHex,
                            staffLineHex: base.staffLineHex,
                            noteHeadHex: base.noteHeadHex,
                            selectedNoteHex: base.selectedNoteHex,
                            barlineHex: base.barlineHex,
                            cursorHex: base.cursorHex,
                            toolbarBackgroundHex: base.toolbarBackgroundHex,
                            colorSchemePreference: base.colorSchemePreference
                        )
                        showCustomThemeEditor = true
                    } label: {
                        Label("Создать тему", systemImage: "plus.circle")
                    }

                    Button {
                        duplicateCurrentTheme()
                    } label: {
                        Label("Дублировать текущую", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle("Темы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .sheet(isPresented: $showCustomThemeEditor) {
                if let theme = editingTheme {
                    ThemeEditorView(theme: theme, isNew: !themeManager.customThemes.contains(where: { $0.id == theme.id }))
                }
            }
        }
    }

    private func duplicateCurrentTheme() {
        let current = themeManager.currentTheme
        let copy = themeManager.duplicateTheme(current, name: current.name + " (копия)")
        themeManager.applyTheme(copy)
        HapticManager.success()
    }
}

// MARK: - Theme Row

struct ThemeRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Color preview strip
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.background)
                        .frame(width: 8, height: 32)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.surface)
                        .frame(width: 8, height: 32)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.accent)
                        .frame(width: 8, height: 32)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.staffLine)
                        .frame(width: 8, height: 32)
                }
                .padding(2)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .font(.body)
                    Text(theme.colorSchemePreference.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Editor

struct ThemeEditorView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State var theme: AppTheme
    let isNew: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Основное") {
                    TextField("Название", text: $theme.name)

                    Picker("Цветовая схема", selection: $theme.colorSchemePreference) {
                        ForEach(ThemeColorScheme.allCases, id: \.self) { scheme in
                            Text(scheme.displayName).tag(scheme)
                        }
                    }
                }

                Section("Интерфейс") {
                    ColorEditRow(label: "Акцент", hex: $theme.accentHex)
                    ColorEditRow(label: "Фон", hex: $theme.backgroundHex)
                    ColorEditRow(label: "Поверхность", hex: $theme.surfaceHex)
                    ColorEditRow(label: "Текст основной", hex: $theme.textPrimaryHex)
                    ColorEditRow(label: "Текст вторичный", hex: $theme.textSecondaryHex)
                    ColorEditRow(label: "Тулбар", hex: $theme.toolbarBackgroundHex)
                }

                Section("Нотный стан") {
                    ColorEditRow(label: "Линии стана", hex: $theme.staffLineHex)
                    ColorEditRow(label: "Ноты", hex: $theme.noteHeadHex)
                    ColorEditRow(label: "Выделенная нота", hex: $theme.selectedNoteHex)
                    ColorEditRow(label: "Тактовая черта", hex: $theme.barlineHex)
                    ColorEditRow(label: "Курсор", hex: $theme.cursorHex)

                    HStack {
                        Text("Прозрачность линий")
                        Spacer()
                        Slider(value: $theme.staffLineOpacity, in: 0.1...1.0, step: 0.05)
                            .frame(width: 150)
                        Text("\(Int(theme.staffLineOpacity * 100))%")
                            .font(.caption)
                            .frame(width: 36)
                    }
                }

                // Preview
                Section("Предпросмотр") {
                    ThemePreviewCard(theme: theme)
                        .frame(height: 80)
                        .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle(isNew ? "Новая тема" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveTheme()
                    }
                    .disabled(theme.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func saveTheme() {
        if isNew {
            themeManager.addCustomTheme(theme)
        } else {
            if let idx = themeManager.customThemes.firstIndex(where: { $0.id == theme.id }) {
                themeManager.customThemes[idx] = theme
            }
        }
        themeManager.applyTheme(theme)
        HapticManager.success()
        dismiss()
    }
}

// MARK: - Color Edit Row

struct ColorEditRow: View {
    let label: String
    @Binding var hex: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: hex))
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            TextField("#RRGGBB", text: $hex)
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Theme Preview Card

struct ThemePreviewCard: View {
    let theme: AppTheme

    var body: some View {
        ZStack {
            Color(hex: theme.backgroundHex)

            VStack(spacing: 4) {
                // Mini staff lines
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle()
                        .fill(Color(hex: theme.staffLineHex).opacity(theme.staffLineOpacity))
                        .frame(height: 1)
                }

                HStack(spacing: 8) {
                    // Note heads
                    Circle()
                        .fill(Color(hex: theme.noteHeadHex))
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(Color(hex: theme.noteHeadHex))
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(Color(hex: theme.selectedNoteHex))
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(Color(hex: theme.noteHeadHex))
                        .frame(width: 10, height: 10)
                }

                Text(theme.name)
                    .font(.caption2)
                    .foregroundColor(Color(hex: theme.textSecondaryHex))
            }
            .padding(8)
        }
    }
}

// MARK: - ThemeColorScheme Display Names

extension ThemeColorScheme {
    var displayName: String {
        switch self {
        case .light: return String(localized: "Светлая")
        case .dark: return String(localized: "Тёмная")
        case .system: return String(localized: "Системная")
        }
    }
}
