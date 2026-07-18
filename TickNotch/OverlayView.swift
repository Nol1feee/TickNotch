import SwiftUI

/// Геометрия бара, посчитанная контроллером от реального выреза экрана.
struct NotchLayout: Equatable {
    var hasNotch: Bool
    var notchWidth: CGFloat
    var barHeight: CGFloat
    var leftWidth: CGFloat
    var rightWidth: CGFloat

    var totalWidth: CGFloat { leftWidth + notchWidth + rightWidth }
}

struct OverlayView: View {
    @ObservedObject var monitor: FocusMonitor
    let layout: NotchLayout

    var body: some View {
        if let session = monitor.session {
            NotchBarView(session: session, layout: layout)
        }
    }
}

/// Чёрный бар вплотную к верхнему краю экрана, визуально продолжающий вырез:
/// слева от выреза — точка состояния и задача, справа — таймер.
private struct NotchBarView: View {
    let session: FocusSession
    let layout: NotchLayout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 7, height: 7)
                    Text(session.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .frame(width: layout.leftWidth)

                if layout.hasNotch {
                    Spacer(minLength: 0)
                        .frame(width: layout.notchWidth)
                }

                Text(timeText(at: context.date))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: layout.rightWidth)
            }
            .frame(width: layout.totalWidth, height: layout.barHeight)
            .foregroundStyle(.white)
            .background(
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                    .fill(Color.black)
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            AppModel.shared.openFocusSticky()
        }
        .help("Открыть заметку задачи")
    }

    private var stateColor: Color {
        switch session.phase {
        case .focus:
            return Color(red: 0.91, green: 0.36, blue: 0.29) // томатный
        case .relax:
            return Color(red: 0.35, green: 0.78, blue: 0.50) // зелёный
        case .pause:
            return Color(red: 0.95, green: 0.68, blue: 0.25) // янтарный
        }
    }

    private func timeText(at now: Date) -> String {
        let value: TimeInterval
        switch session.kind {
        case .pomo:
            value = session.remaining(at: now) ?? 0
        case .stopwatch:
            value = session.elapsed(at: now)
        }
        let suffix = session.phase == .pause ? " ⏸" : ""
        return Self.format(value) + suffix
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
