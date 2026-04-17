#if canImport(UIKit)
import SwiftUI

enum DS {
    static let cornerRadius: CGFloat = 8
}

struct TintedChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                Color.accentColor.opacity(0.15),
                in: RoundedRectangle(cornerRadius: DS.cornerRadius)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct InlineErrorText: View {
    let message: String
    init(_ message: String) { self.message = message }
    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.red)
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    let duration: Duration

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Text(message)
                        .font(.callout)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: message)
            .task(id: message) {
                guard message != nil else { return }
                try? await Task.sleep(for: duration)
                if !Task.isCancelled { message = nil }
            }
    }
}

extension View {
    func toast(_ message: Binding<String?>, duration: Duration = .seconds(1.5)) -> some View {
        modifier(ToastModifier(message: message, duration: duration))
    }
}
#endif
