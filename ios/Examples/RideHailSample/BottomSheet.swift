import SwiftUI

enum SheetDetent: CaseIterable { case collapsed, half, expanded }

/// Reports its (animated) value on every frame of an animation, so the map padding follows the sheet.
/// A small custom bottom sheet with three detents. `visibleHeight` (sheet + keyboard lift) is
/// reported continuously so the host can call `controller.setPadding`.
struct BottomSheet<Content: View>: View {
    @Binding var detent: SheetDetent
    let totalHeight: CGFloat
    let safeBottom: CGFloat
    let topReserve: CGFloat
    let lift: CGFloat
    let onVisibleHeight: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    @GestureState private var drag: CGFloat = 0

    private var collapsedHeight: CGFloat { 150 + safeBottom }
    private var halfHeight: CGFloat { max(collapsedHeight + 120, totalHeight * 0.46) }
    private var expandedHeight: CGFloat { max(halfHeight + 60, totalHeight - topReserve) }

    private func height(_ d: SheetDetent) -> CGFloat {
        switch d { case .collapsed: collapsedHeight; case .half: halfHeight; case .expanded: expandedHeight }
    }

    private var visible: CGFloat { min(expandedHeight, max(collapsedHeight, height(detent) - drag)) }

    var body: some View {
        VStack(spacing: 0) {
            handle
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        .padding(.bottom, safeBottom)
        .frame(height: visible, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 14, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
        .padding(.bottom, lift)
        // Report the visible height on first appearance and on every change (drag, detent, keyboard).
        .onChange(of: visible + lift, initial: true) { _, height in onVisibleHeight(height) }
        .accessibilityIdentifier("ride-sheet")
    }

    private var handle: some View {
        Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 40, height: 5)
            .frame(maxWidth: .infinity).frame(height: 26)
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel("Sheet handle")
            .accessibilityHint("Drag, or activate to change the sheet size")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { cycle() }
            .onTapGesture { cycle() }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .updating($drag) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        let projected = height(detent) - value.predictedEndTranslation.height
                        let target = SheetDetent.allCases.min { abs(height($0) - projected) < abs(height($1) - projected) } ?? detent
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { detent = target }
                    }
            )
    }

    private func cycle() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            detent = detent == .collapsed ? .half : (detent == .half ? .expanded : .collapsed)
        }
    }
}
