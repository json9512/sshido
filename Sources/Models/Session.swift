import Foundation

public struct Session: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let hostID: UUID
    public var title: String
    public let createdAt: Date
    public let tmuxName: String?

    public init(id: UUID = UUID(), hostID: UUID, title: String, createdAt: Date = Date(), tmuxName: String? = nil) {
        self.id = id
        self.hostID = hostID
        self.title = title
        self.createdAt = createdAt
        self.tmuxName = tmuxName
    }
}
