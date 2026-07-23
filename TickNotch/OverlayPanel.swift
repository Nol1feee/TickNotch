import AppKit
import SwiftUI
import Combine

/// Прозрачный AppKit-ловец клика ПОВЕРХ SwiftUI-бара.
/// Окно панели non-activating (никогда не key), поэтому клик по нему — всегда «первый»,
/// а SwiftUI onTapGesture его теряет (первый клик активирует окно, а не доходит до вью).
/// Этот NSView сам — верхний hit-target: acceptsFirstMouse=true + прямой mouseDown.
final class ClickCatcherView: NSView {
    var onClick: () -> Void = {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func hitTest(_ point: NSPoint) -> NSView? { self } // забираем все клики
}

/// Бар у выреза: вплотную к верхнему краю экрана, чёрный, сливается с чёлкой.
/// Поверх всех приложений, включая fullscreen.
@MainActor
final class OverlayPanelController {
    private let panel: NSPanel
    private let hosting: NSHostingView<OverlayView>
    private let clickCatcher = ClickCatcherView()
    private let monitor: FocusMonitor
    private var cancellables = Set<AnyCancellable>()
    /// Текущий экранный прямоугольник бара — для монитора мыши.
    private var barFrame: NSRect = .zero
    private var mouseMonitors: [Any] = []

    init(monitor: FocusMonitor) {
        self.monitor = monitor

        hosting = NSHostingView(rootView: OverlayView(monitor: monitor, layout: NotchLayout(
            hasNotch: false, notchWidth: 0, barHeight: 32, leftWidth: 160, rightWidth: 70
        )))

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        let container = NSView()
        hosting.translatesAutoresizingMaskIntoConstraints = false
        clickCatcher.translatesAutoresizingMaskIntoConstraints = false
        clickCatcher.onClick = { AppModel.shared.openFocusTask() }
        clickCatcher.toolTip = "Открыть задачу в TickTick"
        container.addSubview(hosting)
        container.addSubview(clickCatcher) // поверх бара
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            clickCatcher.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            clickCatcher.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            clickCatcher.topAnchor.constraint(equalTo: container.topAnchor),
            clickCatcher.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container

        Publishers.CombineLatest(monitor.$session, monitor.$overlayEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] session, enabled in
                self?.refresh(session: session, enabled: enabled)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in self.reposition() }
        }

        installMouseMonitors()
    }

    /// Строка меню/вырез могут перехватывать клики в верхней полосе, и окно их не получает.
    /// Поэтому ловим клик по координатам бара напрямую (для мыши accessibility не нужен):
    /// global — клики, ушедшие другим приложениям/меню; local — наши собственные.
    private func installMouseMonitors() {
        let handle: (NSPoint) -> Void = { [weak self] loc in
            Task { @MainActor in self?.handleClick(at: loc) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            handle(NSEvent.mouseLocation)
        } { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            handle(NSEvent.mouseLocation)
            return event
        } { mouseMonitors.append(local) }
    }

    private func handleClick(at location: NSPoint) {
        guard monitor.session != nil, monitor.overlayEnabled,
              barFrame.contains(location) else { return }
        AppModel.shared.openFocusTask()
    }

    private func refresh(session: FocusSession?, enabled: Bool) {
        guard enabled, session != nil else {
            panel.orderOut(nil)
            return
        }
        reposition(session: session)
        barFrame = panel.frame
        panel.orderFrontRegardless()
    }

    func reposition(session: FocusSession? = nil) {
        let session = session ?? monitor.session
        guard let session, let screen = Self.targetScreen() else { return }

        let layout = Self.layout(for: session, on: screen)
        hosting.rootView = OverlayView(monitor: monitor, layout: layout)

        let frame = screen.frame
        let x: CGFloat
        if layout.hasNotch, let leftArea = screen.auxiliaryTopLeftArea {
            // Левая секция заканчивается ровно на левой кромке выреза
            x = leftArea.maxX - layout.leftWidth
        } else {
            x = frame.midX - layout.totalWidth / 2
        }
        let y = frame.maxY - layout.barHeight
        panel.setFrame(NSRect(x: x, y: y, width: layout.totalWidth, height: layout.barHeight), display: true)
    }

    private static func layout(for session: FocusSession, on screen: NSScreen) -> NotchLayout {
        let notchInset = screen.safeAreaInsets.top
        var notchWidth: CGFloat = 0
        if notchInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchWidth = right.minX - left.maxX
        }
        let hasNotch = notchWidth > 0

        // Высота: у выреза — его высота; иначе — высота строки меню
        let barHeight = hasNotch
            ? notchInset
            : max(24, screen.frame.maxY - screen.visibleFrame.maxY)

        // Ширина секций — по фактическому тексту
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let titleWidth = ceil((session.title as NSString).size(withAttributes: [.font: titleFont]).width)
        let leftWidth = min(230, 14 + 7 + 7 + titleWidth + 10)

        let showsHours: Bool = {
            let now = Date()
            let value = session.kind == .stopwatch
                ? session.elapsed(at: now)
                : (session.remaining(at: now) ?? 0)
            return value >= 3600
        }()
        let timeSample = (showsHours ? "8:88:88" : "88:88") + (session.phase == .pause ? " ⏸" : "")
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let rightWidth = ceil((timeSample as NSString).size(withAttributes: [.font: timeFont]).width) + 26

        return NotchLayout(
            hasNotch: hasNotch,
            notchWidth: notchWidth,
            barHeight: barHeight,
            leftWidth: leftWidth,
            rightWidth: rightWidth
        )
    }

    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}
