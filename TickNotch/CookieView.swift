import AppKit
import SwiftUI

@MainActor
final class CookieWindowController: NSWindowController {
    convenience init(model: AppModel) {
        let hosting = NSHostingController(rootView: CookieView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "TickNotch — cookie TickTick"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct CookieView: View {
    let model: AppModel

    @State private var cookie: String = KeychainStore.load() ?? ""
    @State private var result: String?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cookie из ticktick.com")
                .font(.headline)
            Text("""
            1. Залогинься на ticktick.com в браузере.
            2. DevTools (⌥⌘I) → Application → Cookies → https://ticktick.com → скопируй значение cookie «t».
            Либо: вкладка Network → любой запрос к api.ticktick.com → скопируй весь заголовок Cookie (надёжнее: там же будет _csrf_token).
            """)
            .font(.caption)
            .foregroundStyle(.secondary)

            TextEditor(text: $cookie)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 72)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))

            HStack {
                if let result {
                    Text(result).font(.caption)
                }
                Spacer()
                Button("Сохранить и проверить") { saveAndTest() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(testing || cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 460)
    }

    private func saveAndTest() {
        let value = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.save(value)
        testing = true
        result = "Проверяю…"
        Task {
            do {
                let response = try await TickTickClient(cookie: value).fetchCurrentFocus()
                result = response.current != nil
                    ? "✅ Работает, фокус-сессия найдена"
                    : "✅ Работает (активной сессии сейчас нет)"
                model.monitor.pollNow()
            } catch TickTickClient.ClientError.unauthorized {
                result = "❌ 401 — токен не подходит или протух"
            } catch {
                result = "⚠️ Ошибка: \(error.localizedDescription)"
            }
            testing = false
        }
    }
}
