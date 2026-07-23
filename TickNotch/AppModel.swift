import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let monitor = FocusMonitor()

    @Published private(set) var launchAtLogin: Bool = false

    private var panelController: OverlayPanelController?
    private var cookieWindowController: CookieWindowController?
    private let taskWebWindow = TaskWebWindowController()

    private static let tickTickBundleID = "com.TickTick.task.mac"
    private var lastOpenAt = Date.distantPast

    private init() {}

    func bootstrap() {
        panelController = OverlayPanelController(monitor: monitor)
        refreshLaunchAtLogin()
        monitor.start()
        if CookieStore.load() == nil {
            showCookieWindow()
        }
    }

    // MARK: - Открыть задачу фокуса в TickTick

    /// Клик по бару: переключиться в TickTick прямо на задачу фокуса.
    /// Кастомная схема `ticktick://…/tasks/{id}` задачу НЕ открывает (только активирует прилу);
    /// а форс веб-URL приложением `open -a TickTick https://ticktick.com/webapp/#q/all/tasks/{id}`
    /// раскрывает деталь задачи. projectId не нужен — маршрут `#q/all/…` проектонезависимый.
    /// Никакой сети: чистый локальный open, срабатывает мгновенно.
    func openFocusTask() {
        let now = Date()
        guard now.timeIntervalSince(lastOpenAt) > 0.6 else { return } // антидубль (ClickCatcher + монитор)
        lastOpenAt = now
        let taskId = monitor.session?.taskId
        guard let taskId, !taskId.isEmpty else {
            openTickTick() // фокус без задачи
            return
        }
        // Плавающее окно задачи поверх экрана (WKWebView с веб-клиентом TickTick).
        taskWebWindow.show(taskId: taskId)
    }

    // MARK: - Автозапуск при входе (macOS 13+)

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("TickNotch launch-at-login error: \(error)")
        }
        refreshLaunchAtLogin()
    }

    // MARK: - Cookie / прочее

    func showCookieWindow() {
        if cookieWindowController == nil {
            cookieWindowController = CookieWindowController(model: self)
        }
        cookieWindowController?.show()
    }

    func openTickTick() {
        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: Self.tickTickBundleID) {
            workspace.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else if let webURL = URL(string: "https://ticktick.com/webapp") {
            workspace.open(webURL)
        }
    }

    func copyLastResponse() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(monitor.lastRawResponse ?? "нет данных — сначала введи cookie и дождись опроса", forType: .string)
    }
}
