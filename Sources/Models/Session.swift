import Foundation

public struct Session: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let hostID: UUID
    public var title: String
    public let createdAt: Date

    public init(id: UUID = UUID(), hostID: UUID, title: String, createdAt: Date = Date()) {
        self.id = id
        self.hostID = hostID
        self.title = title
        self.createdAt = createdAt
    }
}
