import Foundation
import GRDB

/// A single ledger entry.
///
/// `amount` is stored as REAL. `category` is free text on purpose: users type
/// their own categories and we never normalised them (see CHANGELOG 1.0).
public struct Transaction: Codable, Equatable, Hashable, Sendable {
    public var id: Int64?
    public var walletId: Int64
    public var amount: Double
    public var category: String
    public var note: String?
    public var occurredAt: Date

    public init(
        id: Int64? = nil,
        walletId: Int64,
        amount: Double,
        category: String,
        note: String? = nil,
        occurredAt: Date
    ) {
        self.id = id
        self.walletId = walletId
        self.amount = amount
        self.category = category
        self.note = note
        self.occurredAt = occurredAt
    }
}

extension Transaction: FetchableRecord, MutablePersistableRecord {
    // "transaction" is an SQL keyword. GRDB quotes it in the query interface;
    // any raw SQL must write it as "transaction" with double quotes.
    public static let databaseTableName = "transaction"

    public static let wallet = belongsTo(Wallet.self)

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let walletId = Column(CodingKeys.walletId)
        public static let amount = Column(CodingKeys.amount)
        public static let category = Column(CodingKeys.category)
        public static let note = Column(CodingKeys.note)
        public static let occurredAt = Column(CodingKeys.occurredAt)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
