import Foundation

public struct Session: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let hostID: UUID
    public var title: String
    public let createdAt: Date
    public var tmuxName: String?
    public var tmuxSessionID: String?
    // tmux reissues "$0" after a server restart; this proves the id is still our session.
    public var tmuxCreatedAt: Date?

    public init(
        id: UUID = UUID(),
        hostID: UUID,
        title: String,
        createdAt: Date = Date(),
        tmuxName: String? = nil,
        tmuxSessionID: String? = nil,
        tmuxCreatedAt: Date? = nil
    ) {
        self.id = id
        self.hostID = hostID
        self.title = title
        self.createdAt = createdAt
        self.tmuxName = tmuxName
        self.tmuxSessionID = tmuxSessionID
        self.tmuxCreatedAt = tmuxCreatedAt
    }
}
