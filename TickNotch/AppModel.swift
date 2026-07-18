import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let monitor = FocusMonitor()

    @Published private(set) var launchAtLogin: Bool = false

    private var panelController: OverlayPanelController?
    private var cookieWindowController: CookieWindowController?
    private var stickyTask: Task<Void, Never>?
    /// taskId → projectId (deep-link стики требует projectId в пути).
    private var projectIdCache: [String: String] = [:]

    private init() {}

    func bootstrap() {
        panelController = OverlayPanelController(monitor: monitor)
        refreshLaunchAtLogin()
        monitor.start()
        if KeychainStore.load() == nil {
            showCookieWindow()
        }
    }

    // MARK: - Родная стики-заметка задачи

    /// Клик по бару: открыть встроенную стики-заметку TickTick для задачи фокуса,
    /// плавающую поверх окон, БЕЗ вывода приложения на передний план.
    func openFocusSticky() {
        guard let session = monitor.session,
              let taskId = session.taskId, !taskId.isEmpty else {
            openTickTick() // фокус без привязанной задачи
            return
        }
        if let projectId = projectIdCache[taskId] {
            openSticky(projectId: projectId, taskId: taskId)
            return
        }
        stickyTask?.cancel()
        stickyTask = Task { [weak self] in
            guard let self, let cookie = KeychainStore.load() else {
                self?.openTickTick()
                return
            }
            do {
                let detail = try await TickTickClient(cookie: cookie).fetchTask(id: taskId)
                guard !Task.isCancelled else { return }
                if detail.projectId.isEmpty {
                    openTickTick()
                } else {
                    projectIdCache[taskId] = detail.projectId
                    openSticky(projectId: detail.projectId, taskId: taskId)
                }
            } catch {
                openTickTick()
            }
        }
    }

    private func openSticky(projectId: String, taskId: String) {
        guard let url = URL(string: "ticktick://ticktick.com/p/\(projectId)/tasks/\(taskId)") else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false // как `open -g`: не выводить TickTick на передний план
        NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)
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
        if let appURL = workspace.urlForApplication(withBundleIdentifier: "com.TickTick.task.mac") {
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
