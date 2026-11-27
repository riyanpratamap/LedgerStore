import Foundation

/// Used by the wallet list and wallet detail screens since 1.0.0.
/// Balances come from `TransactionRepository.balance(for:)`.
public enum BalanceFormatter {
    /// The balance string shown to the user, in the given locale's currency style.
    public static func displayString(for balance: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: balance)) ?? ""
    }

    /// The cents a user saw, read back from the formatted USD string.
    ///
    /// `balance` must be finite: a NaN or infinite balance is not displayed as cents.
    public static func displayedCents(for balance: Double) -> Int64 {
        precondition(balance.isFinite, "BalanceFormatter.displayedCents: balance is \(balance)")

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.currencyCode = "USD"

        guard let formatted = formatter.string(from: NSNumber(value: balance)) else {
            preconditionFailure("BalanceFormatter.displayedCents: cannot format \(balance)")
        }

        let negative = formatted.contains("-") || formatted.contains("\u{2212}") || formatted.contains("(")
        let digits = formatted.filter(\.isASCIIDigit)
        guard let magnitude = Int64(digits) else {
            preconditionFailure("BalanceFormatter.displayedCents: no cents in \"\(formatted)\"")
        }
        return negative ? -magnitude : magnitude
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
