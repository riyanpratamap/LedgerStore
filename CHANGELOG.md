# Changelog

All notable changes to LedgerStore, the persistence layer of LedgerLite.
Schema identifiers refer to `DatabaseMigrator` migration names.

## [Unreleased]

### Tooling
- `SeedTool` executable: builds `ledger_v1.sqlite` (3 wallets, 5,000 transactions,
  including the legacy rows listed under Known issues) and `golden_snapshot.json`
  with per-wallet balances of the clean rows in integer cents, and the flagged rows
  listed with the value the v1 database stores. Fixed seed; output is byte-identical
  between runs.

## [1.2.1] - 2024-03-18

### Fixed
- Amount text field limits input to 2 decimal places again (regressed in 1.1.0).

### Known issues
- Shortcuts import and paste-into-amount skip the decimal-places check, so rows with
  3 decimals (e.g. `12.345`) can still be written. Not fixed in the store layer.

## [1.2.0] - 2023-11-06

### Added
- Indexes `transaction_on_walletId` and `transaction_on_occurredAt`. Wallet detail
  screen was doing a full scan on wallets with ~2k rows.

### Changed
- Indexes were added to `v1-initial` instead of a new migration, with
  `CREATE INDEX` run at launch for existing installs (removed in 1.2.1 once
  telemetry showed all active installs on 1.2.x). `v1-initial` is now frozen:
  any further schema change gets its own migration.

## [1.1.0] - 2023-06-01

### Added
- Optional `note` on `Transaction`. Rows created before 1.1 have `note = NULL`.

### Changed
- `note` column was added to `v1-initial` and existing databases were patched with
  `ALTER TABLE ... ADD COLUMN` behind a `PRAGMA table_info` check. Same caveat as 1.2.0.

### Regressed
- Amount field lost its 2-decimal limit during the keypad rewrite (fixed in 1.2.1).

## [1.0.3] - 2023-05-22

### Fixed
- Amounts typed with a comma decimal separator (`12,50`) were parsed with
  `Double(text) ?? .nan` and written through string-built SQL, storing the TEXT
  value `'nan'` in the REAL `amount` column. Writes now go through GRDB records.

### Known issues
- Existing `'nan'` rows were not cleaned up. `SUM(amount)` treats them as 0;
  record decoding turns them into `Double.nan`.

## [1.0.0] - 2023-01-02

### Added
- Initial release. Schema `v1-initial`: `wallet` and `transaction` tables,
  `transaction.walletId` → `wallet.id` (ON DELETE CASCADE).
- `WalletRepository`, `TransactionRepository` with `balance(for:)` as `SUM(amount)`.
- `category` is free text. No category table on purpose: users wanted their own labels.
- Amounts stored as `Double` (SQLite REAL).
- Balances are displayed by formatting the `Double` from `balance(for:)` with
  `NumberFormatter` (`.currency` style, default rounding mode `.halfEven`).
