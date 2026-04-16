#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

@MainActor
public final class HotkeyState: ObservableObject {
    @Published public var armed: Set<HotkeyKind.Modifier> = []
    public init() {}

    public func toggle(_ m: HotkeyKind.Modifier) {
        if armed.contains(m) { armed.remove(m) } else { armed.insert(m) }
    }

    public func consumeAndApply(to bytes: [UInt8]) -> [UInt8] {
        defer { armed.removeAll() }
        guard !armed.isEmpty else { return bytes }
        var out = bytes
        if armed.contains(.ctrl), out.count == 1 {
            let b = out[0]
            if b >= 0x40 && b <= 0x7e {
                out[0] = b & 0x1f
            } else if b >= 0x60 && b <= 0x7a {
                out[0] = (b - 0x20) & 0x1f
            }
        }
        if armed.contains(.shift), out.count == 1 {
            let b = out[0]
            if b >= 0x61 && b <= 0x7a { out[0] = b - 0x20 }
        }
        if armed.contains(.alt) {
            out = [0x1b] + out
        }
        return out
    }
}

public struct AgentBar: View {
    let channel: SSHChannel
    @ObservedObject var hotkeys: HotkeyState
    @State private var customs: [CustomShortcut] = []

    public init(channel: SSHChannel, hotkeys: HotkeyState) {
        self.channel = channel
        self.hotkeys = hotkeys
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 15))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                ForEach(HotkeyButton.defaults) { btn in
                    button(for: btn)
                }
                if !customs.isEmpty {
                    Divider().frame(height: 24)
                    ForEach(customs) { sc in
                        Button {
                            send(bytes: sc.bytes)
                        } label: {
                            Text(sc.label)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
        .task { customs = await CustomShortcutStore.shared.shortcuts }
    }

    @ViewBuilder
    private func button(for btn: HotkeyButton) -> some View {
        let isModifier: HotkeyKind.Modifier? = {
            if case let .modifier(m) = btn.kind { return m } else { return nil }
        }()
        let isArmed = isModifier.map { hotkeys.armed.contains($0) } ?? false
        Button {
            tap(btn)
        } label: {
            HStack(spacing: 4) {
                if let symbol = btn.sfSymbol { Image(systemName: symbol).font(.system(size: 13)) }
                Text(btn.label).font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                isArmed ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(isArmed ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func tap(_ btn: HotkeyButton) {
        switch btn.kind {
        case .modifier(let m):
            hotkeys.toggle(m)
        case .rawBytes(let bytes):
            send(bytes: bytes)
        }
    }

    private func send(bytes: [UInt8]) {
        let final = hotkeys.consumeAndApply(to: bytes)
        Task { try? await channel.send(final) }
    }
}
#endif
