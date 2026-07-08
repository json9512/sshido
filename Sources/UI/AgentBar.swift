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
    let dictator: SpeechDictator
    let voiceEnabled: Bool
    let dictationLocaleID: String
    let onNotice: (String) -> Void
    @State private var items: [BarItem] = []
    @State private var keyboardVisible = true

    public init(channel: SSHChannel,
                bridge: TerminalBridge? = nil,
                hotkeys: HotkeyState,
                dictator: SpeechDictator,
                voiceEnabled: Bool,
                dictationLocaleID: String,
                onNotice: @escaping (String) -> Void = { _ in },
                onFocusTerminal: @escaping () -> Void) {
        self.channel = channel
        self.bridge = bridge
        self.hotkeys = hotkeys
        self.dictator = dictator
        self.voiceEnabled = voiceEnabled
        self.dictationLocaleID = dictationLocaleID
        self.onNotice = onNotice
        self.onFocusTerminal = onFocusTerminal
    }

    public var body: some View {
        VStack(spacing: 0) {
            if voiceEnabled, dictator.isListening {
                transcriptStrip
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    keyboardToggleButton
                    if voiceEnabled { micButton }
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
        }
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

    private var keyboardToggleButton: some View {
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
    }

    private var micButton: some View {
        let listening = dictator.isListening
        let accent = Color(red: 0.353, green: 0.784, blue: 0.839)
        return Button {
            if listening {
                dictator.stop()
            } else {
                Task {
                    guard await dictator.requestAuthorization() else {
                        if case .unavailable(let reason) = dictator.state { onNotice(reason) }
                        return
                    }
                    dictator.start(localeID: dictationLocaleID) { text in
                        send(dictated: text)
                    }
                    if case .unavailable(let reason) = dictator.state { onNotice(reason) }
                }
            }
        } label: {
            Image(systemName: listening ? "mic.fill" : "mic")
                .font(.system(size: 15))
                .foregroundStyle(listening ? accent : Color(red: 232/255, green: 232/255, blue: 237/255))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(
                    listening ? accent.opacity(0.20) : Color(red: 36/255, green: 36/255, blue: 41/255),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(listening ? "Stop dictation" : "Dictate")
    }

    private var transcriptStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.353, green: 0.784, blue: 0.839))
            Text(dictator.partialTranscript.isEmpty ? "Listening…" : dictator.partialTranscript)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color(red: 232/255, green: 232/255, blue: 237/255))
                .lineLimit(1).truncationMode(.head)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 20/255, green: 20/255, blue: 24/255))
    }

    private func send(dictated text: String) {
        guard !text.isEmpty else { return }
        Task { try? await channel.send(Array(text.utf8)) }
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
