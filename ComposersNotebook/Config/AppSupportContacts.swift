import Foundation
import UIKit

/// Контакты поддержки приложения.
///
/// Заполняются перед публикацией в App Store. Пока пустые — кнопки в UI
/// остаются видны (для тестирования вёрстки), но при тапе показывают
/// предупреждение "контакт пока не настроен".
///
/// После заполнения и пересборки приложения кнопки начинают вести на
/// реальные mailto/tg URL.
enum AppSupportContacts {

    // MARK: - Контакты (заполнить перед релизом)

    /// Email для писем от пользователей.
    static let email: String = ""

    /// Telegram username (без @, например "TimShega").
    static let telegramUsername: String = ""

    /// Сайт приложения (опционально).
    static let website: String? = nil

    // MARK: - Производные

    static var isEmailConfigured: Bool { !email.isEmpty }
    static var isTelegramConfigured: Bool { !telegramUsername.isEmpty }
    static var isAnyContactConfigured: Bool { isEmailConfigured || isTelegramConfigured }

    /// URL для открытия письма с предзаполненной техинформацией.
    static func makeMailURL(subject: String, body: String) -> URL? {
        guard isEmailConfigured else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    /// URL для открытия Telegram-чата.
    /// Использует https://t.me/... — открывается в Telegram-приложении, если установлено,
    /// иначе в браузере на странице t.me.
    static func makeTelegramURL() -> URL? {
        guard isTelegramConfigured else { return nil }
        return URL(string: "https://t.me/\(telegramUsername)")
    }

    // MARK: - Диагностика

    /// Авто-формируемая техинформация для писем поддержки.
    /// Включает модель устройства, версию iOS, версию приложения, дату.
    @MainActor
    static func deviceDiagnosticsString() -> String {
        let device = UIDevice.current
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())

        return """
        ---
        \(String(localized: "Auto-generated diagnostics:"))
        \(String(localized: "Device:")) \(device.model)
        \(String(localized: "iOS:")) \(device.systemVersion)
        \(String(localized: "App version:")) \(version) (build \(build))
        \(String(localized: "Date:")) \(timestamp)
        ---
        """
    }
}
