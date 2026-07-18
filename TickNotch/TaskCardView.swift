import SwiftUI

struct TaskCardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.cardPhase {
            case .hidden:
                EmptyView()
            case .loading:
                header(title: model.monitor.session?.title ?? "Задача")
                loadingRow
            case .noTask:
                header(title: model.monitor.session?.title ?? "Фокус")
                infoRow("Фокус без привязанной задачи")
            case .error(let message):
                header(title: model.monitor.session?.title ?? "Задача")
                infoRow("⚠️ " + message)
            case .loaded:
                if let task = model.cardTask {
                    loadedCard(task)
                } else {
                    infoRow("Пусто")
                }
            }
        }
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .padding(6)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Секции

    @ViewBuilder
    private func loadedCard(_ task: TaskDetail) -> some View {
        header(title: task.title.isEmpty ? "Без названия" : task.title, done: task.done)

        VStack(alignment: .leading, spacing: 10) {
            if !task.tags.isEmpty || task.priorityLabel != nil || task.dueText != nil {
                metaRow(task)
            }

            if !task.note.isEmpty {
                ScrollView {
                    Text(task.note)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }

            if !task.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(task.items) { item in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(item.done ? Color.green : Color.secondary)
                            Text(item.title)
                                .font(.system(size: 12))
                                .strikethrough(item.done, color: .secondary)
                                .foregroundStyle(item.done ? .secondary : .primary)
                        }
                    }
                }
            }

            if task.note.isEmpty && task.items.isEmpty {
                infoRow("Без заметки и подзадач")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 2)
    }

    private func metaRow(_ task: TaskDetail) -> some View {
        HStack(spacing: 6) {
            if let priority = task.priorityLabel {
                tag(priority, color: priorityColor(task.priority))
            }
            if let due = task.dueText {
                tag("🕑 " + due, color: .secondary)
            }
            ForEach(task.tags, id: \.self) { name in
                tag("#" + name, color: .accentColor)
            }
        }
    }

    private func header(title: String, done: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .strikethrough(done, color: .secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                AppModel.shared.hideTaskCard()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Загрузка…").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func infoRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 5: return .red
        case 3: return .orange
        case 1: return .blue
        default: return .secondary
        }
    }
}
