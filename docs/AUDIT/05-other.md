# Ось 5 — Прочее (локализация, устройство, App Store, доки, edge-кейсы)

Статус: **код/конфиг-пасс пройден 11.07.2026** (греп + чтение конфигов, коммит cf0e9c0). Осталась
только часть, требующая устройства. Эталоны App Store/HIG/локализации сверены с developer.apple.com
(см. источники внизу).

## С чем сверять

- **Локализация**: строки через `LocalizedStringKey`/`.strings`, а не хардкод. У нас UI на
  русском — проверить, вынесены ли строки или зашиты.
- **App Store**: Info.plist (usage descriptions для микрофона/файлов), иконки всех размеров,
  privacy manifest (обязателен), поддерживаемые ориентации/устройства.
- **Поведение на устройстве**: восстановление после `mediaServicesWereReset`, фон/возврат,
  нехватка памяти при больших SF2, автосейв.
- **Доки**: README, ENGRAVING_REFERENCE, экран лицензий SoundFont (правило
  `feedback_soundfont_license_protocol`).

## Находки из код-аудита

### O-1 ✅ Восстановление аудио после сброса медиа-служб корректно, но теряет позицию
- **У нас**: `MIDIEngine.handleMediaServicesReset` (:141-147) прочитан — `stop()` + `isSoundFontLoaded=false` + `rebuildAudioGraph()` (:149-159: пересоздаёт engine/sampler/EQ/reverb, перегружает SoundFont). Восстановление ЗВУКА корректно и авто (Директива №0 — комментарий :143 это прямо декларирует). Теряется только позиция воспроизведения (stop в начало).
- **Стандарт**: media reset — восстановить граф (сделано ✅) и по возможности позицию.
- **Критичность**: low. Сам recovery — правильный; потеря позиции при редком краше медиа-сервера приемлема. Не дефект, а возможное улучшение.

### O-2 ✅ SoundFont: ошибки загрузки молча гасятся, нет фидбэка юзеру
- **У нас**: `MIDIEngine.loadSoundFont` (:164-177) прочитан — `catch` только `print(...)` + `isSoundFontLoaded=false`, без UI-фидбэка. Смягчение: `loadActiveSoundFont` (:180+) при отсутствии активного SF откатывается на встроенный `TimGM6mb.sf2`. Но если пользовательский импортированный SF2 битый — юзер молча остаётся без своего звука/в тишине, без объяснения.
- **Стандарт**: граница (файл/аудио) — обработка с фидбэком, не silent `print`. Директива №0: recovery = UI-форма + алерт.
- **Критичность**: medium (fallback есть, объяснения нет).

### O-3 🔎 Codable: `decodeIfPresent ?? default` для отсутствующих полей
- **У нас**: напр. `voiceType` дефолтит в `.section` (Part.swift:52). Разумно для миграции,
  но по многим полям это может тихо терять данные старого/чужого файла.
- **Стандарт**: миграция версий файла — явная, с версией схемы, а не «молча дефолт».
- **Критичность**: low-medium (зависит от полей; проверить весь Codable-слой).

### O-4 ✅ Экран лицензий SoundFont — есть и корректен (правило протокола закрыто)
- **У нас**: `LicensesView` (AboutView.swift:84-114) — три секции: `builtInSoundFonts`, `downloadableSoundFonts`,
  `fonts`; каждый ресурс через `LicenseRow` с именем автора и текстом лицензии. Комментарий :82-83:
  «attribution автора обязательно, независимо от того, активирован ли ресурс». TimGM6mb помечен
  `GPL-compatible` (:131). Заголовок и вводный текст локализованы через `String(localized:)`.
- **Стандарт**: лицензии CC BY / MIT требуют указания автора для ВСЕХ встроенных ресурсов (правило
  `feedback_soundfont_license_protocol`).
- **Вердикт**: ✅ соответствует. Пункт закрыт положительно. (При добавлении нового SF/шрифта — дописать сюда.)

### O-5 🔴 НЕТ privacy-манифеста при используемом UserDefaults — БЛОКЕР App Store
- **У нас**: `UserDefaults.standard` используется (Theme.swift:180,186,188,242,244; ComposersNotebookApp.swift:49,55;
  SoundFontManager.swift:93,95,101). Файла `PrivacyInfo.xcprivacy` в проекте **НЕТ** (`find . -name "*.xcprivacy"` пусто).
- **Стандарт**: с 01.05.2024 Apple **отклоняет** (ITMS-91053) приложения, вызывающие «required-reason API» без
  privacy-манифеста. `UserDefaults` — как раз такой API, категория `CA92.1` (app-only). ([TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest))
- **Критичность**: 🔴 **релиз-блокер**. Починка простая: добавить `PrivacyInfo.xcprivacy` с
  `NSPrivacyAccessedAPITypes` = `NSPrivacyAccessedAPICategoryUserDefaults` / reason `CA92.1`,
  `NSPrivacyTracking=false`, пустой `NSPrivacyCollectedDataTypes`. Плюс подключить файл в `project.yml`.

### O-6 🔴 НЕТ иконки приложения (нет asset-каталога) — БЛОКЕР App Store + вид «недоделано»
- **У нас**: `project.yml:98` ссылается на `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`, но в проекте
  **нет ни одного `.xcassets`**, нет `AppIcon.appiconset`, нет ни одного png/pdf/svg (`find` по репозиторию пусто).
  В собранном `.app` иконок тоже нет. На телефоне приложение — с пустым/белым значком.
- **Стандарт**: иконка обязательна; достаточно одного `1024×1024` без альфа-канала в asset-каталоге (Xcode
  сгенерирует остальное).
- **Критичность**: 🔴 релиз-блокер + сразу читается как незаконченное. Починка: создать `Assets.xcassets`
  с `AppIcon.appiconset` (одна картинка 1024). Нужен рисунок иконки — вопрос к Тимуру (дизайн).

### O-7 🟡 ~20 зашитых кириллических строк в обход String Catalog
- **У нас**: каталог `Localizable.xcstrings` — 300 ключей, ключи **английские** (базовый язык = en, ru — перевод).
  Но есть литералы русского прямо в коде: `Text("Прозрачность линий")` (ThemeSettingsView:188) и ещё ~15
  в `Label/Button/navigationTitle/Section`. Часть «ложные» (динамика темпа `♩= \(bpm)`, `Октава \(n)` — норма).
- **Стандарт**: `Text("литерал")` = `LocalizedStringKey`, извлекается; но зашитый **русский** литерал при
  базовом en не переведётся на английский → у не-русского юзера останется русский текст. Для рантайм-строк —
  `String(localized:)`. ([String Catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog))
- **Критичность**: medium. Вынести реальные leak-строки в каталог; отфильтровать динамические (они ок).

## Проверить (осталось — требует устройства)

1. 🔎 Edge: пустая партитура, 0 тактов, партии разной длины (см. E-1), огромные SF2 — часть по коду, часть тыком.
2. 🔎 Автосейв на устройстве: восстановление после реального краша/выгрузки из памяти (код-логика уже
   верифицирована в осях 01/02 — фиктивный autosave починен коммитом 19a0ab3, be9e06b).

## Источники (эталон)
- [TN3183 — Required reason API entries](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Localizing with a string catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
