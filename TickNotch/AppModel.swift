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
        if CookieStore.load() == nil {
            showCookieWindow()
        }
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
