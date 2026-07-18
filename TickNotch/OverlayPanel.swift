import AppKit
import SwiftUI
import Combine

/// Бар у выреза: вплотную к верхнему краю экрана, чёрный, сливается с чёлкой.
/// Поверх всех приложений, включая fullscreen.
@MainActor
final class OverlayPanelController {
    private let panel: NSPanel
    private let hosting: NSHostingView<OverlayView>
    private let monitor: FocusMonitor
    private var cancellables = Set<AnyCancellable>()

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
        panel.contentView = hosting

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
    }

    private func refresh(session: FocusSession?, enabled: Bool) {
        guard enabled, session != nil else {
            panel.orderOut(nil)
            return
        }
        reposition(session: session)
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
