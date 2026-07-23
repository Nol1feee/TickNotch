import AppKit
import WebKit

/// Плавающее окно задачи поверх всех приложений (включая fullscreen).
/// Внутри — WKWebView с веб-клиентом TickTick, авторизованным нашим cookie `t`,
/// открытым на конкретной задаче. Редактируемо: правки уходят в тот же аккаунт.
@MainActor
final class TaskWebWindowController: NSObject, WKNavigationDelegate {
    private var panel: NSPanel?
    private var webView: WKWebView?
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private var loadedCookieHash: Int?
    private var shownAt = Date.distantPast
    private var projectIdCache: [String: String] = [:]

    func show(taskId: String) {
        let panel = ensurePanel()
        loadTask(taskId: taskId)
        position(panel)
        shownAt = Date()
        NSApp.setActivationPolicy(.regular)   // временно, чтобы окно вышло на передний план и принимало ввод
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        installDismissMonitors()
    }

    func hide() {
        removeDismissMonitors()
        panel?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory) // вернуть menu-bar режим
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Резолвим projectId (нужен вебу), потом грузим `#p/{pid}/tasks/{tid}`.
    private func loadTask(taskId: String) {
        if let pid = projectIdCache[taskId] {
            loadURL(projectId: pid, taskId: taskId)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            var pid: String?
            if let cookie = CookieStore.load() {
                pid = try? await TickTickClient(cookie: cookie).fetchProjectId(taskId: taskId)
            }
            if let pid { projectIdCache[taskId] = pid }
            loadURL(projectId: pid, taskId: taskId)
        }
    }

    private func loadURL(projectId: String?, taskId: String) {
        let path = projectId.map { "#p/\($0)/tasks/\(taskId)" } ?? "#q/all/tasks/\(taskId)"
        guard let url = URL(string: "https://ticktick.com/webapp/\(path)") else { return }
        setCookiesThenLoad(url: url)
    }

    // MARK: - Построение

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let config = WKWebViewConfiguration()
        // CSS-срез временно выключен — сначала смотрим, что грузится.
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 460, height: 640), configuration: config)
        web.navigationDelegate = self
        if #available(macOS 13.3, *) { web.isInspectable = true }
        webView = web

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = true
        p.contentView = web
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        panel = p
        return p
    }

    /// Cookie в WKWebView пишется АСИНХРОННО — грузим URL только после записи всех,
    /// иначе первый запрос уходит без авторизации и webapp отдаёт пустую/логин-страницу.
    private func setCookiesThenLoad(url: URL) {
        guard let web = webView else { return }
        let request = URLRequest(url: url)
        guard let raw = CookieStore.load() else { web.load(request); return }
        let store = web.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = Self.parseCookies(raw).compactMap { name, value in
            HTTPCookie(properties: [
                .domain: ".ticktick.com", .path: "/", .name: name, .value: value,
                .secure: "TRUE", .expires: Date(timeIntervalSinceNow: 31_536_000),
            ])
        }
        guard !cookies.isEmpty else { web.load(request); return }
        var remaining = cookies.count
        for cookie in cookies {
            store.setCookie(cookie) { [weak self] in
                remaining -= 1
                if remaining == 0 {
                    self?.webView?.load(request)
                }
            }
        }
    }

    /// "t=xxx; _csrf_token=yyy" -> [(t,xxx),(_csrf_token,yyy)]; голый токен -> [(t, token)].
    static func parseCookies(_ raw: String) -> [(String, String)] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("=") else { return [("t", trimmed)] }
        return trimmed.split(separator: ";").compactMap { part in
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { return nil }
            return (kv[0].trimmingCharacters(in: .whitespaces), kv[1].trimmingCharacters(in: .whitespaces))
        }
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame
        let size = panel.frame.size
        let x = f.midX - size.width / 2
        let y = f.maxY - size.height - 48 // под вырезом
        panel.setFrameOrigin(NSPoint(x: x, y: max(f.minY + 20, y)))
    }

    // MARK: - Закрытие

    private func installDismissMonitors() {
        removeDismissMonitors()
        // Клик мимо окна — закрыть. Но не первые 0.4с и не по самой панели.
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                if Date().timeIntervalSince(self.shownAt) < 0.4 { return }
                if panel.frame.contains(NSEvent.mouseLocation) { return }
                self.hide()
            }
        }
        // Esc — закрыть.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.hide() }; return nil }
            return event
        }
    }

    private func removeDismissMonitors() {
        [outsideMonitor, keyMonitor].forEach { if let m = $0 { NSEvent.removeMonitor(m) } }
        outsideMonitor = nil
        keyMonitor = nil
    }
}
