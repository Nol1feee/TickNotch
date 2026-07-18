import Foundation
import SwiftUI

/// Опрашивает TickTick каждые `baseInterval` секунд, между опросами отсчёт тикает локально (в OverlayView).
/// Ошибки сети — экспоненциальный бэкофф и скрытие оверлея; 401 — редкий опрос до смены cookie.
@MainActor
final class FocusMonitor: ObservableObject {
    enum Status: Equatable {
        case starting
        case ok
        case noCookie
        case unauthorized
        case network
    }

    @Published private(set) var session: FocusSession?
    @Published private(set) var status: Status = .starting
    @Published var overlayEnabled: Bool {
        didSet { UserDefaults.standard.set(overlayEnabled, forKey: Self.overlayKey) }
    }

    private(set) var lastRawResponse: String?

    private static let overlayKey = "TickNotchOverlayEnabled"
    private static let pointKey = "TickNotchLastPoint"
    private let baseInterval: TimeInterval = 3
    private var loopTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var lastPoint = UserDefaults.standard.integer(forKey: FocusMonitor.pointKey)

    init() {
        overlayEnabled = UserDefaults.standard.object(forKey: Self.overlayKey) as? Bool ?? true
    }

    func start() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.poll()
                let interval = self.nextInterval()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func pollNow() {
        Task { await poll() }
    }

    private func nextInterval() -> TimeInterval {
        switch status {
        case .unauthorized:
            return 120
        case .noCookie:
            return 15
        case .network:
            // 6, 12, 24, 48 … максимум 5 минут
            return min(300, baseInterval * pow(2, Double(min(consecutiveFailures, 6))))
        case .ok, .starting:
            return baseInterval
        }
    }

    private func poll() async {
        guard let cookie = CookieStore.load() else {
            status = .noCookie
            session = nil
            return
        }

        let client = TickTickClient(cookie: cookie)
        do {
            let result = try await client.fetchCurrentFocus(lastPoint: lastPoint)
            lastRawResponse = result.rawJSON
            session = FocusParser.session(from: result.current)
            status = .ok
            consecutiveFailures = 0
            if let point = result.point {
                lastPoint = point
                UserDefaults.standard.set(point, forKey: Self.pointKey)
            }
        } catch TickTickClient.ClientError.unauthorized {
            status = .unauthorized
            session = nil
        } catch {
            consecutiveFailures += 1
            status = .network
            // Одну осечку прощаем (локальный тик сгладит), после второй прячем оверлей.
            if consecutiveFailures >= 2 {
                session = nil
            }
        }
    }
}
