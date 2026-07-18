import Foundation

/// Хранение cookie TickTick в защищённом файле (права 0600) в Application Support.
///
/// Почему не Keychain: приложение подписано ad-hoc, и Keychain привязывает доступ к
/// подписи кода. Каждая пересборка меняет подпись → macOS считает приложение «другим»
/// и бесконечно требует пароль от login-keychain. Файл под аккаунтом пользователя этого
/// лишён; cookie и так извлекается из браузера, так что secret-уровень тот же.
enum CookieStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TickNotch", isDirectory: true)
    }

    private static var fileURL: URL {
        directory.appendingPathComponent("cookie", isDirectory: false)
    }

    static func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = trimmed.data(using: .utf8) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        // Права 0600 — читает только владелец.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func load() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty
        else { return nil }
        return string
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
