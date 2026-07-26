import Foundation

struct FocusSession: Equatable {
    enum Phase: Equatable {
        case focus
        case pause
        case relax
    }

    enum Kind: Equatable {
        case pomo
        case stopwatch
    }

    var title: String
    var taskId: String?
    var phase: Phase
    var kind: Kind
    /// Помидор/перерыв: момент конца отсчёта.
    var endDate: Date?
    /// Помидор на паузе: замороженный остаток.
    var frozenRemaining: TimeInterval?
    /// Секундомер: накоплено к моменту парсинга.
    var elapsedBase: TimeInterval
    var parsedAt: Date
    var rawStatus: Int?

    func remaining(at now: Date) -> TimeInterval? {
        if phase == .pause { return frozenRemaining }
        guard let endDate else { return nil }
        return max(0, endDate.timeIntervalSince(now))
    }

    func elapsed(at now: Date) -> TimeInterval {
        phase == .pause ? elapsedBase : elapsedBase + max(0, now.timeIntervalSince(parsedAt))
    }
}

/// Парсер поля `current` из ответа /focus/batch/focusOp.
/// Семантика полей выведена из живого трафика этого аккаунта (436 сессий) — см. API_NOTES.md:
///   type: 0 = помидор (duration = план в МИНУТАХ), 1 = секундомер (duration = 0)
///   status: 0 = идёт, 2 = завершён (возможен перерыв в focusBreak), 3 = сброшен (drop),
///           прочее (1) = пауза; exited: true = сессия закрыта
///   focusTasks[]: отрезки фокуса {startTime, endTime, title} — паузы = разрывы между ними
enum FocusParser {
    static func session(from current: [String: Any]?, now: Date = Date()) -> FocusSession? {
        guard let cur = current, !cur.isEmpty else { return nil }
        if (cur["valid"] as? Bool) == false { return nil }
        if (cur["exited"] as? Bool) == true { return nil }

        let status = intValue(cur["status"])
        let kind: FocusSession.Kind = intValue(cur["type"]) == 1 ? .stopwatch : .pomo
        let segments = segments(from: cur)
        let title = cleanTitle(segments.reversed()
            .compactMap { $0.title }
            .first { !$0.isEmpty })
        let taskId = segments.reversed()
            .compactMap { $0.id }
            .first { !$0.isEmpty }
        let plannedSeconds = (doubleValue(cur["duration"]) ?? 0) * 60

        switch status {
        case 3:
            return nil // сброшен (drop)

        case 2:
            // Помидор завершён; если идёт перерыв — показываем его отсчёт
            if let breakDict = cur["focusBreak"] as? [String: Any],
               let breakEnd = date(breakDict["endTime"]),
               breakEnd > now {
                return FocusSession(
                    title: "Перерыв",
                    taskId: taskId,
                    phase: .relax,
                    kind: .pomo,
                    endDate: breakEnd,
                    frozenRemaining: nil,
                    elapsedBase: 0,
                    parsedAt: now,
                    rawStatus: status
                )
            }
            return nil

        case 0, nil:
            return runningSession(
                cur: cur, kind: kind, title: title, taskId: taskId, status: status,
                plannedSeconds: plannedSeconds, segments: segments, now: now
            )

        default:
            // 1 и любые неизвестные коды — пауза (сессия жива, но не тикает)
            return pausedSession(
                kind: kind, title: title, taskId: taskId, status: status,
                plannedSeconds: plannedSeconds, segments: segments, now: now
            )
        }
    }

    // MARK: - Состояния

    private static func runningSession(
        cur: [String: Any],
        kind: FocusSession.Kind,
        title: String,
        taskId: String?,
        status: Int?,
        plannedSeconds: TimeInterval,
        segments: [Segment],
        now: Date
    ) -> FocusSession? {
        let closedPrior = segments.dropLast().reduce(0.0) {
            $0 + max(0, ($1.end ?? $1.start).timeIntervalSince($1.start))
        }
        let lastStart = segments.last?.start ?? date(cur["startTime"]) ?? now
        let focusedNow = closedPrior + max(0, now.timeIntervalSince(lastStart))

        if kind == .stopwatch {
            // Зомби-секундомер (TickTick сам обрубает по 12 ч) — не показываем
            if focusedNow > 12 * 3600 { return nil }
            return FocusSession(
                title: title, taskId: taskId, phase: .focus, kind: .stopwatch,
                endDate: nil, frozenRemaining: nil,
                elapsedBase: focusedNow, parsedAt: now, rawStatus: status
            )
        }

        // Помидор: конец = startTime + duration(минуты) [+ время пауз].
        // Проверено против самого TickTick: показывает 53:14 == start+duration-now.
        // Серверный `endTime` НЕ конец помидора (бывает start+90мин при duration=60) — не использовать.
        let pomoStart = date(cur["startTime"]) ?? segments.first?.start ?? now
        let pauseRaw = doubleValue(cur["pauseDuration"]) ?? 0
        let pauseExtra = pauseRaw >= 100_000 ? pauseRaw / 1000 : pauseRaw // ms или сек
        let end: Date
        if plannedSeconds > 0 {
            end = pomoStart.addingTimeInterval(plannedSeconds + pauseExtra)
        } else if let serverEnd = date(cur["endTime"]), serverEnd > now {
            end = serverEnd // fallback, если duration почему-то пуст
        } else {
            end = now.addingTimeInterval(max(0, -focusedNow)) // совсем нет данных — 0
        }
        // Помидор давно должен был кончиться, а статус не обновился — не показываем.
        if now.timeIntervalSince(end) > 120 { return nil }
        return FocusSession(
            title: title, taskId: taskId, phase: .focus, kind: .pomo,
            endDate: end, frozenRemaining: nil,
            elapsedBase: focusedNow, parsedAt: now, rawStatus: status
        )
    }

    private static func pausedSession(
        kind: FocusSession.Kind,
        title: String,
        taskId: String?,
        status: Int?,
        plannedSeconds: TimeInterval,
        segments: [Segment],
        now: Date
    ) -> FocusSession {
        // На паузе последний отрезок закрыт (endTime = момент паузы)
        let closedAll = segments.reduce(0.0) {
            $0 + max(0, ($1.end ?? now).timeIntervalSince($1.start))
        }
        return FocusSession(
            title: title, taskId: taskId, phase: .pause, kind: kind,
            endDate: nil,
            frozenRemaining: kind == .pomo ? max(0, plannedSeconds - closedAll) : nil,
            elapsedBase: closedAll, parsedAt: now, rawStatus: status
        )
    }

    // MARK: - Отрезки фокуса

    private struct Segment {
        let start: Date
        let end: Date?
        let title: String?
        let id: String?
    }

    private static func segments(from cur: [String: Any]) -> [Segment] {
        let raw = (cur["focusTasks"] as? [[String: Any]])
            ?? (cur["focusOnLogs"] as? [[String: Any]])
            ?? []
        return raw.compactMap { dict in
            guard let start = date(dict["startTime"]) ?? date(dict["time"]) else { return nil }
            return Segment(
                start: start,
                end: date(dict["endTime"]),
                title: dict["title"] as? String,
                id: dict["id"] as? String
            )
        }
    }

    // MARK: - Хелперы типов

    /// Чистим заголовок для бара: первая строка, markdown-ссылки [text](url) → text, обрезка.
    static func cleanTitle(_ raw: String?) -> String {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return "Фокус" }
        s = s.components(separatedBy: .newlines).first ?? s
        // [текст](url) -> текст
        while let open = s.range(of: "]("), let lb = s.range(of: "[", range: s.startIndex..<open.lowerBound) {
            if let close = s.range(of: ")", range: open.upperBound..<s.endIndex) {
                let text = String(s[lb.upperBound..<open.lowerBound])
                s.replaceSubrange(lb.lowerBound..<close.upperBound, with: text)
            } else { break }
        }
        // Остатки сырых ссылок/markdown — режем всё от них.
        for marker in ["http://", "https://", "](", " | [", "["] {
            if let r = s.range(of: marker) { s = String(s[s.startIndex..<r.lowerBound]) }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " |—-•").union(.whitespaces))
        if s.count > 60 { s = String(s.prefix(60)).trimmingCharacters(in: .whitespaces) + "…" }
        return s.isEmpty ? "Фокус" : s
    }

    static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let n as Int: return n
        case let n as Double: return Int(n)
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }

    /// Даты: epoch (мс или сек) либо ISO "2026-07-18T13:59:16.852+0000" / без миллисекунд.
    static func date(_ any: Any?) -> Date? {
        if let n = doubleValue(any) {
            if n > 1e12 { return Date(timeIntervalSince1970: n / 1000) }
            if n > 1e9 { return Date(timeIntervalSince1970: n) }
            return nil
        }
        guard let s = any as? String, !s.isEmpty else { return nil }
        return isoFormats.lazy.compactMap { $0.date(from: s) }.first
    }

    private static let isoFormats: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter
        }
    }()
}
