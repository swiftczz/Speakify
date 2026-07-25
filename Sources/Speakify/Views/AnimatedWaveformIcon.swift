import SwiftUI

struct AnimatedWaveformIcon: View {
    let isAnimating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var scale: CGFloat = 1
    private let restingHeights: [CGFloat] = [6, 11, 16, 11, 6]

    private var isMoving: Bool {
        isAnimating && reduceMotion == false
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: isMoving == false)) { timeline in
            HStack(spacing: 2 * scale) {
                ForEach(restingHeights.indices, id: \.self) { index in
                    Capsule()
                        .frame(
                            width: 1.5 * scale,
                            height: barHeight(at: index, date: timeline.date) * scale
                        )
                }
            }
            .frame(width: 20 * scale, height: 18 * scale)
        }
    }

    private func barHeight(at index: Int, date: Date) -> CGFloat {
        guard isMoving else { return restingHeights[index] }
        let time = date.timeIntervalSinceReferenceDate
        let wave = abs(sin(time * 7 + Double(index) * 0.9))
        return 5 + CGFloat(wave) * 12
    }
}
