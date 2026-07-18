import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum CardPhase: Equatable {
        case hidden, loading, loaded, noTask
        case error(String)
    }

    let monitor = FocusMonitor()

    @Published var cardPhase: CardPhase = .hidden
    @Published var cardTask: TaskDetail?
    @Published private(set) var launchAtLogin: Bool = false

    private var panelController: OverlayPanelController?
    private var cardController: TaskCardController?
    private var cookieWindowController: CookieWindowController?
    private var cardFetch: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func bootstrap() {
        panelController = OverlayPanelController(monitor: monitor)
        cardController = TaskCardController(model: self)
        refreshLaunchAtLogin()
        monitor.start()

        // Сессия пропала — прячем карточку.
        monitor.$session
            .receive(on: RunLoop.main)
            .sink { [weak self] session in
                if session == nil { self?.hideTaskCard() }
            }
            .store(in: &cancellables)

        if KeychainStore.load() == nil {
            showCookieWindow()
        }
    }

    // MARK: - Карточка задачи

    func toggleTaskCard() {
        if cardPhase == .hidden {
            presentTaskCard()
        } else {
            hideTaskCard()
        }
    }

    private func presentTaskCard() {
        guard let session = monitor.session else { return }
        guard let taskId = session.taskId, !taskId.isEmpty else {
            cardTask = nil
            cardPhase = .noTask
            cardController?.show()
            return
        }
        cardTask = nil
        cardPhase = .loading
        cardController?.show()

        cardFetch?.cancel()
        cardFetch = Task { [weak self] in
            guard let self else { return }
            guard let cookie = KeychainStore.load() else {
                cardPhase = .error("нет cookie")
                cardController?.relayout()
                return
            }
            do {
                let detail = try await TickTickClient(cookie: cookie).fetchTask(id: taskId)
                guard !Task.isCancelled else { return }
                cardTask = detail
                cardPhase = .loaded
            } catch TickTickClient.ClientError.unauthorized {
                cardPhase = .error("cookie недействителен (401)")
            } catch {
                cardPhase = .error("не удалось загрузить задачу")
            }
            cardController?.relayout()
        }
    }

    func hideTaskCard() {
        cardFetch?.cancel()
        cardPhase = .hidden
        cardController?.hide()
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
