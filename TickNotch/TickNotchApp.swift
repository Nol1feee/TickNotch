import SwiftUI
import AppKit

@main
struct TickNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("TickNotch", systemImage: "timer") {
            MenuContent(model: AppModel.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // На случай запуска бинарника вне бандла (без Info.plist с LSUIElement)
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.bootstrap()
    }
}

struct MenuContent: View {
    @ObservedObject var monitor: FocusMonitor
    @ObservedObject var model: AppModel

    init(model: AppModel) {
        self.model = model
        self.monitor = model.monitor
    }

    var body: some View {
        Text(statusLine)
        Divider()
        Button(monitor.overlayEnabled ? "Скрыть оверлей" : "Показать оверлей") {
            monitor.overlayEnabled.toggle()
        }
        Button("Обновить сейчас") {
            monitor.pollNow()
        }
        Toggle("Запускать при входе", isOn: Binding(
            get: { model.launchAtLogin },
            set: { _ in model.toggleLaunchAtLogin() }
        ))
        Divider()
        Button("Ввести cookie…") {
            model.showCookieWindow()
        }
        Button("Скопировать последний ответ API") {
            model.copyLastResponse()
        }
        Divider()
        Button("Открыть TickTick") {
            model.openTickTick()
        }
        Divider()
        Button("Выйти из TickNotch") {
            NSApp.terminate(nil)
        }
    }

    private var statusLine: String {
        switch monitor.status {
        case .starting:
            return "Запуск…"
        case .noCookie:
            return "Нет cookie — введи токен TickTick"
        case .unauthorized:
            return "⚠️ Cookie недействителен (401)"
        case .network:
            return "⚠️ Нет связи с TickTick, повторяю…"
        case .ok:
            if let session = monitor.session {
                return "Идёт: \(session.title)"
            }
            return "Нет активной фокус-сессии"
        }
    }
}
