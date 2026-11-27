import Foundation
import GRDB

public struct WalletRepository: Sendable {
    private let database: DatabaseManager

    public init(database: DatabaseManager) {
        self.database = database
    }

    @discardableResult
    public func insert(_ wallet: Wallet) throws -> Wallet {
        try database.writer.write { db in
            try wallet.inserted(db)
        }
    }

    public func fetchAll() throws -> [Wallet] {
        try database.reader.read { db in
            try Wallet
                .order(Wallet.Columns.createdAt, Wallet.Columns.id)
                .fetchAll(db)
        }
    }

    public func fetch(id: Int64) throws -> Wallet? {
        try database.reader.read { db in
            try Wallet.fetchOne(db, key: id)
        }
    }
}
