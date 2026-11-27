import GRDB
import XCTest
@testable import LedgerStore

final class LedgerStoreTests: XCTestCase {
    private var tempDir: URL!
    private var database: DatabaseManager!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        database = try DatabaseManager(path: tempDir.appendingPathComponent("ledger.sqlite").path)
    }

    override func tearDownWithError() throws {
        database = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testMigratorRunsOnEmptyDatabase() throws {
        let queue = try DatabaseQueue()
        _ = try DatabaseManager(writer: queue)

        try queue.read { db in
            XCTAssertTrue(try db.tableExists("wallet"))
            XCTAssertTrue(try db.tableExists("transaction"))
            XCTAssertEqual(try DatabaseManager.migrator.appliedMigrations(db), ["v1-initial"])

            let indexed = try db.indexes(on: "transaction").map(\.columns)
            XCTAssertTrue(indexed.contains(["walletId"]))
            XCTAssertTrue(indexed.contains(["occurredAt"]))

            let fks = try db.foreignKeys(on: "transaction")
            XCTAssertEqual(fks.count, 1)
            XCTAssertEqual(fks.first?.destinationTable, "wallet")
        }
    }

    func testInsertAndFetchByWallet() throws {
        let wallets = WalletRepository(database: database)
        let transactions = TransactionRepository(database: database)

        let cash = try wallets.insert(Wallet(name: "Cash"))
        let bank = try wallets.insert(Wallet(name: "Bank"))
        let cashId = try XCTUnwrap(cash.id)
        let bankId = try XCTUnwrap(bank.id)

        let day = Date(timeIntervalSince1970: 1_700_000_000)
        try transactions.insert(Transaction(walletId: cashId, amount: 4.5, category: "Coffee", occurredAt: day))
        try transactions.insert(Transaction(walletId: cashId, amount: 12, category: "lunch", note: "w/ team", occurredAt: day.addingTimeInterval(3600)))
        try transactions.insert(Transaction(walletId: bankId, amount: 1200, category: "Salary", occurredAt: day))

        let fetched = try transactions.fetch(walletId: cashId)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched.map(\.category), ["lunch", "Coffee"])
        XCTAssertEqual(fetched.first?.note, "w/ team")
        XCTAssertNil(fetched.last?.note)
        XCTAssertEqual(try wallets.fetchAll().map(\.name), ["Cash", "Bank"])
    }

    func testBalanceOfSmallWallet() throws {
        let wallets = WalletRepository(database: database)
        let transactions = TransactionRepository(database: database)
        let walletId = try XCTUnwrap(wallets.insert(Wallet(name: "Groceries")).id)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for amount in [25.0, 10.5, -5.5, 100.0] {
            try transactions.insert(Transaction(walletId: walletId, amount: amount, category: "Food", occurredAt: now))
        }

        XCTAssertEqual(try transactions.balance(for: walletId), 130.0, accuracy: 0.001)
    }

    func testBalanceOfEmptyWalletIsZero() throws {
        let wallets = WalletRepository(database: database)
        let transactions = TransactionRepository(database: database)
        let walletId = try XCTUnwrap(wallets.insert(Wallet(name: "Empty")).id)

        XCTAssertEqual(try transactions.balance(for: walletId), 0)
    }
}
