import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public struct AgentLineDecoder: Sendable {
    public enum Output: Equatable, Sendable {
        case event(AgentModeEvent)
        case undecodable(String)
    }

    private let pending: Data

    public init() { self.pending = Data() }
    private init(pending: Data) { self.pending = pending }

    public func feeding(_ chunk: Data) -> (AgentLineDecoder, [Output]) {
        let buffer = pending + chunk
        guard let lastNewline = buffer.lastIndex(of: UInt8(ascii: "\n")) else {
            return (AgentLineDecoder(pending: buffer), [])
        }
        let complete = buffer[buffer.startIndex..<lastNewline]
        let rest = buffer[buffer.index(after: lastNewline)...]
        let outputs = complete.split(separator: UInt8(ascii: "\n")).map(Self.decode)
        return (AgentLineDecoder(pending: Data(rest)), outputs)
    }

    static func decode(_ line: Data.SubSequence) -> Output {
        do {
            return .event(try JSONDecoder().decode(AgentModeEvent.self, from: Data(line)))
        } catch {
            return .undecodable(String(decoding: line, as: UTF8.self))
        }
    }

    public static func encode(_ request: AgentRequest) throws -> Data {
        try JSONEncoder().encode(request) + Data([UInt8(ascii: "\n")])
    }
}
