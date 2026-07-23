import AppKit
import SwiftUI

/// The draggable divider between the window's panes.
struct DragHandle: View {
    /// +1 = leading handle (drag right → wider), -1 = trailing handle (drag right → narrower)
    let direction: Int
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var startWidth: CGFloat = 0

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .overlay {
                Rectangle()
                    .fill(isHovering ? AppPalette.accent.opacity(0.6) : AppPalette.stroke)
                    .frame(width: 1)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startWidth = width
                        }
                        let delta = CGFloat(direction) * value.translation.width
                        width = max(minWidth, min(maxWidth, startWidth + delta))
                    }
                    .onEnded { _ in
                        isDragging = false
                        if !isHovering {
                            NSCursor.pop()
                        }
                    }
            )
    }
}
