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

    private static let tickTickBundleID = "com.TickTick.task.mac"

    private init() {}

    func bootstrap() {
        panelController = OverlayPanelController(monitor: monitor)
        refreshLaunchAtLogin()
        monitor.start()
        if KeychainStore.load() == nil {
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
        guard let session = monitor.session,
              let taskId = session.taskId, !taskId.isEmpty,
              let url = URL(string: "https://ticktick.com/webapp/#q/all/tasks/\(taskId)"),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.tickTickBundleID)
        else {
            openTickTick() // фокус без задачи / TickTick не установлен
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config, completionHandler: nil)
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
