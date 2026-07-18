import Foundation

/// Карточка задачи из GET /api/v2/task/{id}. Приватный API — парсим defensively.
struct TaskDetail: Equatable, Identifiable {
    struct ChecklistItem: Equatable, Identifiable {
        let id: String
        let title: String
        let done: Bool
    }

    let id: String
    let title: String
    /// Заметка задачи: `content` (тип TEXT) или `desc` (тип CHECKLIST).
    let note: String
    let items: [ChecklistItem]
    let priority: Int            // 0 нет, 1 низкий, 3 средний, 5 высокий
    let tags: [String]
    let done: Bool
    let dueDate: Date?
    let isAllDay: Bool

    init(_ dict: [String: Any]) {
        id = dict["id"] as? String ?? ""
        title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let content = (dict["content"] as? String) ?? ""
        let desc = (dict["desc"] as? String) ?? ""
        note = (content.isEmpty ? desc : content).trimmingCharacters(in: .whitespacesAndNewlines)

        priority = FocusParser.intValue(dict["priority"]) ?? 0
        done = (FocusParser.intValue(dict["status"]) ?? 0) != 0
        isAllDay = (dict["isAllDay"] as? Bool) ?? false
        dueDate = FocusParser.date(dict["dueDate"])

        if let rawTags = dict["tags"] as? [String] {
            tags = rawTags
        } else {
            tags = []
        }

        if let rawItems = dict["items"] as? [[String: Any]] {
            items = rawItems.enumerated().map { index, item in
                ChecklistItem(
                    id: (item["id"] as? String) ?? "\(index)",
                    title: (item["title"] as? String) ?? "",
                    done: (FocusParser.intValue(item["status"]) ?? 0) != 0
                )
            }
        } else {
            items = []
        }
    }

    var priorityLabel: String? {
        switch priority {
        case 5: return "Высокий"
        case 3: return "Средний"
        case 1: return "Низкий"
        default: return nil
        }
    }

    var dueText: String? {
        guard let dueDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = isAllDay ? "d MMM" : "d MMM, HH:mm"
        return formatter.string(from: dueDate)
    }
}
