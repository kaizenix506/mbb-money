import 'package:sqflite/sqflite.dart';

/// Opens the local database and owns its migrations.
///
/// The app is **offline-first**: SQLite on device, no backend. Every schema
/// change must bump [version] and add an `onUpgrade` branch so existing users
/// do not lose history.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String fileName = 'mbb_money.db';
  static const int version = 1;

  static final Map<String, Database> _open = <String, Database>{};

  /// Returns the database for [directory]. An empty string (the iOS/Android
  /// default) resolves through sqflite; anything else is treated as an
  /// absolute folder, which is what sqflite_common_ffi needs on desktop.
  Future<Database> databaseIn(String directory) async {
    final Database? existing = _open[directory];
    if (existing != null && existing.isOpen) return existing;
    final Database db = await _openAt(directory);
    _open[directory] = db;
    return db;
  }

  Future<Database> _openAt(String directory) async {
    final String path = directory.isEmpty
        ? fileName
        : '$directory${directory.endsWith('/') || directory.endsWith(r'\') ? '' : '/'}$fileName';
    return openDatabase(
      path,
      version: version,
      onConfigure: (Database db) async {
        // Needed for ON DELETE SET NULL on category_id.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _create,
      onUpgrade: _upgrade,
    );
  }

  Future<void> _create(Database db, int v) async {
    await db.execute('''
      CREATE TABLE transactions (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        type             TEXT    NOT NULL CHECK (type IN ('income','expense','transfer')),
        amount           INTEGER NOT NULL CHECK (amount >= 0),
        occurred_at      INTEGER NOT NULL,
        description      TEXT    NOT NULL DEFAULT '',
        counterparty     TEXT,
        category_id      TEXT,
        source           TEXT    NOT NULL DEFAULT 'manual'
                                 CHECK (source IN ('manual','shortcut','sepay')),
        account_id       TEXT,
        reference_number TEXT,
        raw_text         TEXT,
        created_at       INTEGER NOT NULL,
        pending_review   INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // The overview does `WHERE occurred_at BETWEEN ? AND ? ORDER BY occurred_at DESC`
    // on every frame the month changes, so this index is the hot path.
    await db.execute(
      'CREATE INDEX idx_tx_occurred ON transactions (occurred_at DESC)',
    );

    // Dedupe on reference number during sync. Partial index because manual
    // rows have no reference and must not collide with each other.
    await db.execute('''
      CREATE UNIQUE INDEX idx_tx_reference
        ON transactions (reference_number)
        WHERE reference_number IS NOT NULL
    ''');

    await db.execute(
      'CREATE INDEX idx_tx_category ON transactions (category_id)',
    );

    await db.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE accounts (
        id         TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        bank_key   TEXT NOT NULL,
        last4      TEXT,
        is_default INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _seedAccount(db);
  }

  Future<void> _upgrade(Database db, int from, int to) async {
    // v1 is the initial schema; future migrations append here.
    // Keep this exhaustive so a schema change never silently drops history.
    if (from < 1) {
      await _create(db, to);
    }
  }

  Future<void> _seedAccount(Database db) async {
    final Batch batch = db.batch();
    batch.insert('accounts', <String, Object?>{
      'id': 'mb-bank',
      'name': 'MB Bank',
      'bank_key': 'MB',
      'is_default': 1,
    });
    batch.insert('accounts', <String, Object?>{
      'id': 'cash',
      'name': 'Tiền mặt',
      'bank_key': 'CASH',
      'is_default': 0,
    });
    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    for (final Database db in _open.values) {
      await db.close();
    }
    _open.clear();
  }
}
