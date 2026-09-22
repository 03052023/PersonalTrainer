import Foundation

public struct ProgramTemplate: Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let days: [ProgramDayTemplate]
    public let isActive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        days: [ProgramDayTemplate] = [],
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.days = days
        self.isActive = isActive
    }
}
