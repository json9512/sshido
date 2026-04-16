import Foundation

public struct Identity: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var label: String
    public var keychainTag: String

    public init(id: UUID = UUID(), label: String, keychainTag: String) {
        self.id = id
        self.label = label
        self.keychainTag = keychainTag
    }
}
