// SeedTool: builds the ledger_v1.sqlite fixture and its golden_snapshot.json.
//
//   swift run SeedTool [output-directory]
//
// The DB is what the shipped v1 schema holds after real use, including the
// broken rows older app versions wrote. The snapshot is the ground truth
// computed from what users typed, in Decimal, never via Double.

import Foundation
import GRDB
import LedgerStore

let outputDir = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath,
    isDirectory: true
)
let dbURL = outputDir.appendingPathComponent("ledger_v1.sqlite")
let snapshotURL = outputDir.appendingPathComponent("golden_snapshot.json")

let posix = Locale(identifier: "en_US_POSIX")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("SeedTool: \(message)\n".utf8))
    exit(1)
}

// MARK: - Generate

var generator = Generator()
let rows = generator.makeRows()

guard rows.count == Fixture.transactionCount else { fail("expected \(Fixture.transactionCount) rows, got \(rows.count)") }
for row in rows {
    switch row.kind {
    case .valid:
        guard row.typedAmount.isValidTypedAmount else { fail("row \(row.id): valid row has bad input \(row.typedAmount)") }
    case .nanAmount:
        guard Double(row.typedAmount) == nil else { fail("row \(row.id): NaN input parses: \(row.typedAmount)") }
    case .threeDecimals:
        guard !row.typedAmount.isValidTypedAmount, Double(row.typedAmount) != nil else {
            fail("row \(row.id): expected 3-decimal input, got \(row.typedAmount)")
        }
    }
}

// MARK: - Write the v1 database

try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
for suffix in ["", "-wal", "-shm", "-journal"] {
    try? FileManager.default.removeItem(atPath: dbURL.path + suffix)
}

// DatabaseQueue (rollback journal) keeps the fixture a single file.
// The app itself opens it through DatabaseManager(path:) with a pool.
let queue = try DatabaseQueue(path: dbURL.path)
let database = try DatabaseManager(writer: queue)

try database.writer.write { db in
    for wallet in Fixture.wallets {
        _ = try Wallet(id: wallet.id, name: wallet.name, createdAt: wallet.createdAt).inserted(db)
    }

    for row in rows {
        let walletId = Fixture.wallets[row.walletIndex].id

        // What the app did with the text field: Double(string).
        // 1.0.x fell back to `.nan` on a parse failure.
        let amount = Double(row.typedAmount) ?? .nan

        if amount.isNaN {
            // Reproduces the 1.0.x write path, which built SQL by string
            // interpolation. SQLite turns a bound NaN into NULL (and NOT NULL
            // would reject it), but the quoted literal 'nan' is stored as TEXT
            // in the REAL column. That is what is on users' devices.
            try db.execute(
                sql: """
                    INSERT INTO "transaction" (id, walletId, amount, category, note, occurredAt)
                    VALUES (?, ?, '\(amount)', ?, ?, ?)
                    """,
                arguments: [row.id, walletId, row.category, row.note, row.occurredAt]
            )
        } else {
            _ = try Transaction(
                id: row.id,
                walletId: walletId,
                amount: amount,
                category: row.category,
                note: row.note,
                occurredAt: row.occurredAt
            ).inserted(db)
        }
    }
}

// MARK: - Golden snapshot (Decimal only)

/// Exact cents from the typed string. Decimal parses decimal text exactly.
func cents(_ typed: String) -> Decimal {
    guard let value = Decimal(string: typed, locale: posix) else { fail("unparseable amount \(typed)") }
    return value * 100
}

/// Independent integer-only parse, used to cross-check the Decimal path.
func centsByHand(_ typed: String) -> Int64 {
    let negative = typed.hasPrefix("-")
    let body = negative ? String(typed.dropFirst()) : typed
    let parts = body.split(separator: ".", omittingEmptySubsequences: false)
    let whole = Int64(parts[0])!
    let fraction = parts.count > 1 ? Int64(parts[1].padding(toLength: 2, withPad: "0", startingAt: 0))! : 0
    let value = whole * 100 + fraction
    return negative ? -value : value
}

func exactInt64(_ decimal: Decimal) -> Int64 {
    var input = decimal
    var rounded = Decimal()
    NSDecimalRound(&rounded, &input, 0, .plain)
    guard rounded == decimal, let value = Int64(rounded.description) else {
        fail("\(decimal) is not a whole number of cents")
    }
    return value
}

struct WalletSnapshot: Encodable {
    let id: Int64
    let name: String
    let transactionCount: Int
    let cleanTransactionCount: Int
    let cleanRowsBalanceCents: Int64
}

struct FlaggedRow: Encodable {
    let id: Int64
    let walletId: Int64
    let reason: String
    let storedValue: String
}

struct Snapshot: Encodable {
    let schemaVersion: String
    let seed: UInt64
    let totalTransactionCount: Int
    let cleanTransactionCount: Int
    let flaggedTransactionIds: [Int64]
    let flaggedTransactions: [FlaggedRow]
    let scopeNote: String
    let wallets: [WalletSnapshot]
}

let cleanRows = rows.filter { $0.kind == .valid }
let flaggedRows = rows.filter { $0.kind != .valid }

/// What the v1 database actually holds for a flagged row.
func storedValue(_ row: SeedRow) -> String {
    switch row.kind {
    case .nanAmount: return "nan"
    case .threeDecimals: return row.typedAmount
    case .valid: fail("row \(row.id): clean row is not flagged")
    }
}

let walletSnapshots = Fixture.wallets.enumerated().map { index, wallet -> WalletSnapshot in
    let all = rows.filter { $0.walletIndex == index }
    let valid = all.filter { $0.kind == .valid }
    let total = valid.reduce(Decimal(0)) { $0 + cents($1.typedAmount) }
    let balance = exactInt64(total)
    let check = valid.reduce(Int64(0)) { $0 + centsByHand($1.typedAmount) }
    guard balance == check else { fail("wallet \(wallet.id): Decimal \(balance) != integer \(check)") }
    return WalletSnapshot(
        id: wallet.id,
        name: wallet.name,
        transactionCount: all.count,
        cleanTransactionCount: valid.count,
        cleanRowsBalanceCents: balance
    )
}

let snapshot = Snapshot(
    schemaVersion: "v1-initial",
    seed: Fixture.seed,
    totalTransactionCount: rows.count,
    cleanTransactionCount: cleanRows.count,
    flaggedTransactionIds: flaggedRows.map(\.id).sorted(),
    flaggedTransactions: flaggedRows
        .sorted { $0.id < $1.id }
        .map { FlaggedRow(id: $0.id, walletId: Fixture.wallets[$0.walletIndex].id, reason: $0.kind.rawValue, storedValue: storedValue($0)) },
    scopeNote: "Balances cover only rows typed with up to 2 decimals. Flagged rows are listed as stored and are not part of any total.",
    wallets: walletSnapshots
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
var json = try encoder.encode(snapshot)
json.append(contentsOf: Data("\n".utf8))
try json.write(to: snapshotURL, options: .atomic)

// MARK: - Report

let dbCount = try queue.read { db in try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "transaction""#) ?? 0 }
guard dbCount == Fixture.transactionCount else { fail("DB has \(dbCount) transactions") }

print("Wrote \(dbURL.path)")
print("Wrote \(snapshotURL.path)")
print("transactions: \(rows.count)  clean: \(cleanRows.count)  flagged: \(flaggedRows.count)")

// Clean-row balance next to what the v1 balance(for:) returns. Informational only.
let repository = TransactionRepository(database: database)
for wallet in walletSnapshots {
    let sum = try repository.balance(for: wallet.id)
    let clean = Decimal(wallet.cleanRowsBalanceCents) / 100
    print("wallet \(wallet.id) \(wallet.name): clean rows \(clean)  v1 SUM(amount) \(String(format: "%.10f", sum))")
}
