import Foundation
import GRDB

public struct TransactionRepository: Sendable {
    private let database: DatabaseManager

    public init(database: DatabaseManager) {
        self.database = database
    }

    @discardableResult
    public func insert(_ transaction: Transaction) throws -> Transaction {
        try database.writer.write { db in
            try transaction.inserted(db)
        }
    }

    /// Newest first, matching the wallet detail screen.
    public func fetch(walletId: Int64) throws -> [Transaction] {
        try database.reader.read { db in
            try Transaction
                .filter(Transaction.Columns.walletId == walletId)
                .order(Transaction.Columns.occurredAt.desc, Transaction.Columns.id.desc)
                .fetchAll(db)
        }
    }

    /// SUM(amount) for the wallet. Returns 0 for a wallet with no transactions.
    public func balance(for walletId: Int64) throws -> Double {
        try database.reader.read { db in
            try Double.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(amount), 0)
                    FROM "transaction"
                    WHERE walletId = ?
                    """,
                arguments: [walletId]
            ) ?? 0
        }
    }
}
