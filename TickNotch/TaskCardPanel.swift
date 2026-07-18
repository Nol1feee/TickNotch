import AppKit
import SwiftUI

/// Плавающая карточка задачи под баром у выреза. Поверх всех приложений, включая fullscreen.
@MainActor
final class TaskCardController {
    private let panel: NSPanel
    private let hosting: NSHostingView<TaskCardView>
    private var outsideClickMonitor: Any?

    init(model: AppModel) {
        hosting = NSHostingView(rootView: TaskCardView(model: model))
        hosting.sizingOptions = [.preferredContentSize]

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 352, height: 120),
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
    }

    func show() {
        relayout()
        panel.orderFrontRegardless()
        installOutsideClickMonitor()
    }

    func hide() {
        panel.orderOut(nil)
        removeOutsideClickMonitor()
    }

    /// Пересчёт размера/позиции после загрузки содержимого.
    func relayout() {
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width < 40 { size.width = 352 }
        if size.height < 40 { size.height = 120 }

        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let frame = screen.frame
        let barHeight = max(24, screen.safeAreaInsets.top, frame.maxY - screen.visibleFrame.maxY)

        let x = frame.midX - size.width / 2
        let y = frame.maxY - barHeight - size.height + 2 // лёгкий заход под бар
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    // Клик вне карточки — закрыть.
    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in AppModel.shared.hideTaskCard() }
            _ = self
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
