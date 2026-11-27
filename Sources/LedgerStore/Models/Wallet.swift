import Foundation
import GRDB

public struct Wallet: Codable, Equatable, Hashable, Sendable {
    public var id: Int64?
    public var name: String
    public var createdAt: Date

    public init(id: Int64? = nil, name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

extension Wallet: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "wallet"

    public static let transactions = hasMany(Transaction.self)

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let name = Column(CodingKeys.name)
        public static let createdAt = Column(CodingKeys.createdAt)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
