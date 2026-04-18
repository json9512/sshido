#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoUI)
import sshidoUI
#endif

/// A Metal-rendered surface with a subtle diagonal shimmer effect
/// that simulates light catching brushed titanium.
///
/// Use sparingly on hero surfaces (host cards, AgentBar). Limit to
/// 3-4 simultaneous instances on screen.
struct TitaniumSurface: UIViewRepresentable {
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = DS.Radius.lg) {
        self.cornerRadius = cornerRadius
    }

    func makeUIView(context: Context) -> TitaniumUIView {
        let view = TitaniumUIView()
        view.layer.cornerRadius = cornerRadius
        view.layer.masksToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: TitaniumUIView, context: Context) {
        uiView.layer.cornerRadius = cornerRadius
    }
}

@MainActor
final class TitaniumUIView: UIView {
    private var renderer: ChromeRenderer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(red: 0.102, green: 0.102, blue: 0.122, alpha: 1) // surface1 fallback
        guard let r = ChromeRenderer() else { return }
        renderer = r
        layer.addSublayer(r.metalLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderer?.metalLayer.frame = bounds
        renderer?.metalLayer.drawableSize = CGSize(
            width: bounds.width * (window?.screen.scale ?? UIScreen.main.scale),
            height: bounds.height * (window?.screen.scale ?? UIScreen.main.scale)
        )
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            renderer?.start()
        } else {
            renderer?.stop()
        }
    }
}
#endif
