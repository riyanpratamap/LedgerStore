import Foundation
import GRDB

/// Owns the SQLite connection and the schema migrator.
public final class DatabaseManager: Sendable {
    public let writer: any DatabaseWriter

    /// Opens (or creates) the database file at `path` and migrates it.
    public convenience init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        #if DEBUG
        config.publicStatementArguments = true
        #endif
        let pool = try DatabasePool(path: path, configuration: config)
        try self.init(writer: pool)
    }

    /// Wraps an existing writer. Used by tests with an in-memory `DatabaseQueue`.
    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public var reader: any DatabaseReader { writer }

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // Off on purpose: shipped DBs must never be wiped. Flip locally only.
        // migrator.eraseDatabaseOnSchemaChange = true
        #endif

        // v1-initial was amended in 1.1 (note) and 1.2 (indexes) before we had
        // a second migration. Do not edit it again: add a new migration instead.
        migrator.registerMigration("v1-initial") { db in
            try db.create(table: "wallet") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "transaction") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("walletId", .integer)
                    .notNull()
                    .references("wallet", onDelete: .cascade)
                t.column("amount", .double).notNull()
                t.column("category", .text).notNull()
                t.column("note", .text)
                t.column("occurredAt", .datetime).notNull()
            }

            try db.create(
                index: "transaction_on_walletId",
                on: "transaction",
                columns: ["walletId"]
            )
            try db.create(
                index: "transaction_on_occurredAt",
                on: "transaction",
                columns: ["occurredAt"]
            )
        }

        return migrator
    }
}
