import Foundation

/// One row as the user typed it, before it touches a Double.
struct SeedRow {
    enum Kind: String {
        case valid
        /// 1.0.x parsed "12,50" with the device locale and wrote NaN.
        case nanAmount = "nan_amount"
        /// 1.1.0 amount field had no decimal limit.
        case threeDecimals = "three_decimals"
    }

    let id: Int64
    let walletIndex: Int
    let typedAmount: String
    let category: String
    let note: String?
    let occurredAt: Date
    let kind: Kind
}

struct SeedWallet {
    let id: Int64
    let name: String
    let createdAt: Date
}

enum Fixture {
    static let seed: UInt64 = 20_231_201
    static let transactionCount = 5_000

    /// 2023-01-01T00:00:00Z
    static let epoch = Date(timeIntervalSince1970: 1_672_531_200)
    /// 1.1 shipped notes on 2023-06-01; nothing before that date has one.
    static let notesShippedAt = Date(timeIntervalSince1970: 1_685_577_600)

    static let wallets: [SeedWallet] = [
        SeedWallet(id: 1, name: "Cash", createdAt: epoch),
        SeedWallet(id: 2, name: "Main Account", createdAt: epoch.addingTimeInterval(3_600 * 26)),
        SeedWallet(id: 3, name: "Savings 🏠", createdAt: epoch.addingTimeInterval(86_400 * 40)),
    ]

    /// Classic binary-float traps. Every one of these is inexact as a Double.
    static let trickyAmounts = ["0.29", "0.57", "1.15", "0.1", "0.2", "19.99", "0.3", "0.7", "4.35", "1.10"]

    static let zeroSpellings = ["0.00", "0", "0.0"]

    static let largeAmounts = ["25000000.75", "18450000.10", "9999999.99", "12500000"]

    /// Strings the 1.0.x parser turned into NaN.
    static let nanInputs = ["12,50", "1.234,56", "7,5", "0,99", "15,-", "€3,20"]

    static let threeDecimalInputs = ["12.345", "0.125", "99.999", "3.333", "1250.005", "-4.875"]
}

struct Generator {
    private var rng = SplitMix64(seed: Fixture.seed)

    mutating func makeRows() -> [SeedRow] {
        let n = Fixture.transactionCount

        // Reserve positions up front so counts are exact, not probabilistic.
        // NaN rows only exist in 1.0.x data, i.e. the first ~5 months of ids.
        let nanSlots = rng.distinct(6, below: 1_000)
        let threeDecimalSlots = rng.distinct(6, below: n, excluding: Set(nanSlots))
        let largeSlots = rng.distinct(
            Fixture.largeAmounts.count,
            below: n,
            excluding: Set(nanSlots + threeDecimalSlots)
        )
        let nanBySlot = Dictionary(uniqueKeysWithValues: zip(nanSlots, Fixture.nanInputs))
        let threeBySlot = Dictionary(uniqueKeysWithValues: zip(threeDecimalSlots, Fixture.threeDecimalInputs))
        let largeBySlot = Dictionary(uniqueKeysWithValues: zip(largeSlots, Fixture.largeAmounts))

        // ~2 years of history, ids roughly chronological with some backdating.
        let span: TimeInterval = 86_400 * 730
        let step = span / Double(n)

        var rows: [SeedRow] = []
        rows.reserveCapacity(n)

        for slot in 0..<n {
            var occurredAt = Fixture.epoch.addingTimeInterval(Double(slot) * step + Double(rng.int(Int(step))))
            if rng.chance(4) {
                occurredAt.addTimeInterval(-Double(rng.int(in: 1...20)) * 86_400)
            }
            occurredAt = max(occurredAt, Fixture.epoch)

            let kind: SeedRow.Kind
            let typed: String
            var walletIndex = pickWallet()
            var category: String

            if let value = nanBySlot[slot] {
                kind = .nanAmount
                typed = value
                category = rng.pick(Self.everydayCategories)
            } else if let value = threeBySlot[slot] {
                kind = .threeDecimals
                typed = value
                category = value.hasPrefix("-") ? "Refund" : rng.pick(Self.everydayCategories)
            } else if let value = largeBySlot[slot] {
                kind = .valid
                typed = value
                walletIndex = rng.chance(50) ? 1 : 2
                category = rng.pick(["House", "property", "Car", "Tax", "Investment"])
            } else {
                kind = .valid
                (typed, category) = typedAmount(walletIndex: walletIndex)
            }

            if rng.chance(3) {
                category = category.lowercased()
            }

            rows.append(SeedRow(
                id: Int64(slot + 1),
                walletIndex: walletIndex,
                typedAmount: typed,
                category: category,
                note: note(for: occurredAt),
                occurredAt: occurredAt,
                kind: kind
            ))
        }
        return rows
    }

    private mutating func pickWallet() -> Int {
        let r = rng.int(100)
        if r < 55 { return 0 }
        if r < 90 { return 1 }
        return 2
    }

    private mutating func typedAmount(walletIndex: Int) -> (String, String) {
        let r = rng.int(1_000)
        switch r {
        case 0..<90:
            return (rng.pick(Fixture.trickyAmounts), rng.pick(Self.smallCategories))
        case 90..<105:
            return (rng.pick(Fixture.zeroSpellings), rng.pick(["Adjustment", "Free sample", "Coffee", "Misc"]))
        case 105..<170:
            return ("-" + everydayAmount(maxWhole: 180), rng.pick(["Refund", "refund", "Return", "Cashback"]))
        default:
            let maxWhole = walletIndex == 2 ? 2_500 : 400
            return (everydayAmount(maxWhole: maxWhole), rng.pick(Self.everydayCategories))
        }
    }

    /// How people actually type money: "12", "12.5", "12.50", "12.99".
    private mutating func everydayAmount(maxWhole: Int) -> String {
        // Skew towards small values.
        let a = rng.int(in: 1...maxWhole)
        let b = rng.int(in: 1...maxWhole)
        let whole = rng.chance(70) ? min(a, b) : a
        switch rng.int(100) {
        case 0..<30:
            return "\(whole)"
        case 30..<45:
            return "\(whole).\(rng.int(10))"
        case 45..<60:
            return "\(whole).\(rng.pick(["50", "99", "95", "00", "49"]))"
        default:
            return "\(whole).\(String(format: "%02d", rng.int(100)))"
        }
    }

    private mutating func note(for date: Date) -> String? {
        guard date >= Fixture.notesShippedAt, rng.chance(22) else { return nil }
        return rng.pick(Self.notes)
    }

    private static let smallCategories = [
        "Coffee", "coffee", "Snacks", "Parking", "Bus", "Tip", "Candy", "App Store", "Laundry", "Gum",
    ]

    private static let everydayCategories = [
        "Groceries", "groceries", "Grocery", "Food", "Eating out", "Restaurants", "Transport", "Uber",
        "Fuel", "Rent", "Utilities", "Electricity", "Internet", "Phone", "Health", "Pharmacy",
        "Gym", "Subscriptions", "Netflix", "Shopping", "Clothes", "Gifts", "Kids", "Pets",
        "Travel", "Books", "Entertainment", "Misc", "Other", "Café ☕", "Household",
    ]

    private static let notes = [
        "split w/ Sam", "work trip", "reimbursable", "birthday", "forgot receipt",
        "weekly shop", "paid by card", "cash", "Tokyo 🇯🇵", "deposit", "TODO check",
        "duplicate?", "annual", "school stuff", "vet",
    ]
}

extension String {
    /// `-?digits(.d{1,2})?` — what the current app accepts.
    var isValidTypedAmount: Bool {
        range(of: #"^-?[0-9]+(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil
    }
}
