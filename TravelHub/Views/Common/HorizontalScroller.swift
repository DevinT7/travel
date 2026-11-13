import SwiftUI

/// A horizontal scroll row that also works with a mouse on Mac: click and drag to scroll, and
/// arrow buttons appear at the edges on hover (a plain ScrollView only scrolls sideways there
/// with a trackpad swipe or Shift + scroll wheel). On iPhone and iPad it's a normal ScrollView.
struct HorizontalScroller<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var position = ScrollPosition(edge: .leading)
    @State private var offset: CGFloat = 0
    @State private var maxOffset: CGFloat = 0
    @State private var visibleWidth: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var isHovering = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { content }
            #if os(macOS)
            .scrollPosition($position)
            .onScrollGeometryChange(for: [CGFloat].self) { g in
                [g.contentOffset.x, max(0, g.contentSize.width + g.contentInsets.leading + g.contentInsets.trailing - g.containerSize.width), g.containerSize.width]
            } action: { _, v in
                offset = v[0]; maxOffset = v[1]; visibleWidth = v[2]
            }
            // Only kicks in once the pointer moves, so a plain click still opens the card under it.
            .highPriorityGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        if dragStart == nil { dragStart = offset }
                        position.scrollTo(x: clamp((dragStart ?? 0) - value.translation.width))
                    }
                    .onEnded { value in
                        // Carry on a little in the direction of the flick.
                        let fling = (value.predictedEndTranslation.width - value.translation.width) * 0.6
                        withAnimation(.smooth(duration: 0.35)) {
                            position.scrollTo(x: clamp((dragStart ?? 0) - value.translation.width - fling))
                        }
                        dragStart = nil
                    }
            )
            .overlay(alignment: .leading) {
                if isHovering && offset > 1 { arrow("chevron.left") { page(-1) }.padding(.leading, 6) }
            }
            .overlay(alignment: .trailing) {
                if isHovering && offset < maxOffset - 1 { arrow("chevron.right") { page(1) }.padding(.trailing, 6) }
            }
            .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
            #endif
    }

    #if os(macOS)
    private func clamp(_ x: CGFloat) -> CGFloat { min(max(0, x), maxOffset) }

    private func page(_ direction: CGFloat) {
        withAnimation(.smooth) { position.scrollTo(x: clamp(offset + direction * max(200, visibleWidth * 0.8))) }
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }
    #endif
}
