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
    let bridge: TerminalBridge?
    let onFocusTerminal: () -> Void
    @ObservedObject var hotkeys: HotkeyState
    @State private var items: [BarItem] = []
    @State private var keyboardVisible = true

    public init(channel: SSHChannel,
                bridge: TerminalBridge? = nil,
                hotkeys: HotkeyState,
                onFocusTerminal: @escaping () -> Void) {
        self.channel = channel
        self.bridge = bridge
        self.hotkeys = hotkeys
        self.onFocusTerminal = onFocusTerminal
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    if keyboardVisible {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    } else {
                        onFocusTerminal()
                    }
                } label: {
                    Image(systemName: keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(red: 232/255, green: 232/255, blue: 237/255))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(red: 36/255, green: 36/255, blue: 41/255), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                ForEach(items) { item in
                    switch item {
                    case .builtin(let btn): button(for: btn)
                    case .group(let g):     groupButton(g)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(red: 26/255, green: 26/255, blue: 31/255))
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyLayoutChanged)) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }

    private func reload() async {
        let groups = await ShortcutGroupStore.shared.groups
        items = await HotkeyLayoutStore.shared.ordered(builtins: HotkeyButton.defaults, groups: groups)
    }

    @ViewBuilder
    private func groupButton(_ g: ShortcutGroup) -> some View {
        Menu {
            if g.shortcuts.isEmpty {
                Text("No shortcuts yet")
            } else {
                ForEach(g.shortcuts) { sc in
                    Button {
                        send(bytes: sc.bytes)
                    } label: {
                        Text(sc.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let sym = g.sfSymbol, !sym.isEmpty {
                    Image(systemName: sym).font(.system(size: 13))
                }
                Text(g.label)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(Color(red: 232/255, green: 232/255, blue: 237/255))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                Color(red: 0.353, green: 0.784, blue: 0.839).opacity(0.15),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .menuOrder(.fixed)
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
            .foregroundStyle(isArmed ? Color.white : Color(red: 232/255, green: 232/255, blue: 237/255))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                isArmed ? Color(red: 0.353, green: 0.784, blue: 0.839).opacity(0.55) : Color(red: 36/255, green: 36/255, blue: 41/255),
                in: RoundedRectangle(cornerRadius: 8)
            )
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
        let swapped = applicationCursorSwap(bytes)
        let final = hotkeys.consumeAndApply(to: swapped)
        Task { try? await channel.send(final) }
    }

    private func applicationCursorSwap(_ bytes: [UInt8]) -> [UInt8] {
        guard bridge?.isApplicationCursor == true,
              bytes.count == 3,
              bytes[0] == 0x1b,
              bytes[1] == 0x5b
        else { return bytes }
        switch bytes[2] {
        case 0x41, 0x42, 0x43, 0x44:
            return [0x1b, 0x4f, bytes[2]]
        default:
            return bytes
        }
    }
}
#endif
