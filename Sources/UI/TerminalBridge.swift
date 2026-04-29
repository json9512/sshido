#if canImport(UIKit)
import Foundation

public enum CopyKind { case selection, viewport }

@MainActor
public protocol TerminalBridge: AnyObject {
    func feed(_ data: Data)
    func refit()
    func focus()
    func applyAppearance() async
    func copyFromTerminal(_ kind: CopyKind) async -> String
    func snapshotBufferLines(beforeViewport: Int, afterViewport: Int) -> [String]
    func requestServerRedraw()
    var hasSelection: Bool { get }
    var cols: Int { get }
    var isApplicationCursor: Bool { get }
    var onTitleChange: ((String) -> Void)? { get set }
    var activityTracker: TerminalActivityTracker { get }
}
#endif
