#if canImport(UIKit)
import SwiftUI

/// A pixel-art cat companion that sits in the terminal overlay.
/// Draggable. Renders at 8fps with nearest-neighbor scaling.
public struct MascotSpriteView: View {
    let state: MascotSpriteState
    let sheets: [MascotMood: SpriteSheet]
    let displaySize: CGFloat
    let containerSize: CGSize
    let onHide: () -> Void
    let onMirror: () -> Void
    @Binding var offset: CGSize
    @Binding var mirrored: Bool

    public init(state: MascotSpriteState, sheets: [MascotMood: SpriteSheet], displaySize: CGFloat = 48, containerSize: CGSize, offset: Binding<CGSize>, mirrored: Binding<Bool>, onHide: @escaping () -> Void, onMirror: @escaping () -> Void) {
        self.state = state
        self.sheets = sheets
        self.displaySize = displaySize
        self.containerSize = containerSize
        self.onHide = onHide
        self.onMirror = onMirror
        self._offset = offset
        self._mirrored = mirrored
    }

    @GestureState private var dragDelta: CGSize = .zero

    public var body: some View {
        let live = clamped(CGSize(
            width:  offset.width  + dragDelta.width,
            height: offset.height + dragDelta.height
        ))
        TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { context in
            SpriteFrame(
                mood: state.currentMood,
                extraName: state.currentExtra,
                frameIndex: state.currentFrame,
                sheets: sheets,
                extraSheets: state.extraSheets,
                displaySize: displaySize
            )
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .onChange(of: context.date) { _, _ in
                state.tick()
            }
        }
        .offset(x: live.width, y: live.height)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                state.cycleToNext()
            }
        )
        .contextMenu {
            Button {
                onMirror()
            } label: {
                Label(mirrored ? "Unmirror" : "Mirror", systemImage: "arrow.left.arrow.right")
            }
            Button(role: .destructive) {
                onHide()
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }
        }
        .gesture(
            DragGesture()
                .updating($dragDelta) { value, delta, _ in
                    delta = value.translation
                }
                .onEnded { value in
                    offset = clamped(CGSize(
                        width:  offset.width  + value.translation.width,
                        height: offset.height + value.translation.height
                    ))
                }
        )
    }

    private func clamped(_ s: CGSize) -> CGSize {
        let pad: CGFloat = 8
        let minX = -(containerSize.width  - displaySize - pad)
        let minY = -(containerSize.height - displaySize - pad)
        return CGSize(
            width:  min(0, max(minX, s.width)),
            height: min(0, max(minY, s.height))
        )
    }
}

/// Pure rendering view — no mutations in body.
private struct SpriteFrame: View {
    let mood: MascotMood
    let extraName: String?
    let frameIndex: Int
    let sheets: [MascotMood: SpriteSheet]
    let extraSheets: [String: SpriteSheet]
    let displaySize: CGFloat

    var body: some View {
        let sheet: SpriteSheet? = {
            if let name = extraName {
                return extraSheets[name]
            }
            return sheets[mood] ?? sheets[.sitting]
        }()
        if let sheet {
            Image(uiImage: sheet.frame(at: frameIndex))
                .interpolation(.none)
                .resizable()
                .frame(width: displaySize, height: displaySize)
        }
    }
}
#endif
