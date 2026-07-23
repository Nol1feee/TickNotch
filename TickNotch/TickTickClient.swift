import Foundation

/// Клиент приватного веб-API TickTick.
/// Текущая фокус-сессия: POST https://ms.ticktick.com/focus/batch/focusOp
/// (см. API_NOTES.md — что подтверждено, что нет).
struct TickTickClient {
    let cookie: String

    enum ClientError: Error {
        case unauthorized
        case http(Int)
        case badPayload
    }

    struct FocusOpResult {
        let current: [String: Any]?
        let point: Int?
        let rawJSON: String
    }

    private static let endpoint = URL(string: "https://ms.ticktick.com/focus/batch/focusOp")!

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"

    /// Не шлём cookie из общего хранилища системы — только наш заголовок.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Стабильный device id (24 hex) — TickTick различает устройства по X-Device.id.
    private static let deviceID: String = {
        let key = "TickNotchDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = String((0..<24).map { _ in "0123456789abcdef".randomElement()! })
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }()

    /// `lastPoint` — курсор синка из прошлого ответа; с актуальным значением
    /// ответ ~1 КБ вместо сотен КБ истории в `updates`. `current` возвращается всегда.
    func fetchCurrentFocus(lastPoint: Int = 0) async throws -> FocusOpResult {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["lastPoint": lastPoint, "opList": [[String: Any]]()])
        applyHeaders(&request)

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badPayload }
        if http.statusCode == 401 || http.statusCode == 403 { throw ClientError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.http(http.statusCode) }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else { throw ClientError.badPayload }

        let pretty = (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? String(data: data, encoding: .utf8)
            ?? "<не декодируется>"

        return FocusOpResult(
            current: dict["current"] as? [String: Any],
            point: dict["point"] as? Int,
            rawJSON: pretty
        )
    }

    private func applyHeaders(_ request: inout URLRequest) {
        let normalized = Self.normalizeCookie(cookie)
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://ticktick.com", forHTTPHeaderField: "Origin")
        request.setValue("https://ticktick.com/webapp/", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "x-tz")
        request.setValue(Self.deviceHeader, forHTTPHeaderField: "X-Device")
        request.setValue(normalized, forHTTPHeaderField: "Cookie")
        if let csrf = Self.cookieValue(named: "_csrf_token", in: normalized) {
            request.setValue(csrf, forHTTPHeaderField: "x-csrftoken")
        }
    }

    private static var deviceHeader: String {
        let device: [String: Any] = [
            "platform": "web",
            "os": "macOS",
            "device": "Chrome 136.0.0.0",
            "name": "",
            "version": 6310,
            "id": deviceID,
            "channel": "website",
            "campaign": "",
            "websocket": "",
        ]
        let data = (try? JSONSerialization.data(withJSONObject: device, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Принимает: голый токен, "t=...", либо полный заголовок Cookie.
    static func normalizeCookie(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("=") { return trimmed }
        return "t=\(trimmed)"
    }

    static func cookieValue(named name: String, in cookieHeader: String) -> String? {
        for pair in cookieHeader.components(separatedBy: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces) == name {
                return String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
