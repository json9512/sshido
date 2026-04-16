#if canImport(UIKit)
import Foundation

public enum CopyKind { case selection, viewport, lastURL }

@MainActor
public protocol TerminalBridge: AnyObject {
    func feed(_ data: Data)
    func refit()
    func focus()
    func applyAppearance() async
    func copyFromTerminal(_ kind: CopyKind) async -> String
}
#endif
