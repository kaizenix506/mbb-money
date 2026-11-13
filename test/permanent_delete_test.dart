import 'package:flutter_test/flutter_test.dart';
import 'package:mbb_money/data/db/transaction_dao.dart';
import 'package:mbb_money/data/models/transaction.dart';
import 'package:mbb_money/data/models/tx_source.dart';
import 'package:mbb_money/data/repositories/transaction_repository.dart';
// `sqflite_common` exports its own `Transaction` (an SQL transaction handle),
// which collides with the domain model imported above.
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// Permanent delete must survive a SePay re-sync.
///
/// SePay pulls a rolling 3-day window and de-duplicates on `reference_number`,
/// so a row that was merely `DELETE`d would be re-inserted on the next sync.
/// These tests pin the tombstone behaviour that prevents that.
void main() {
  sqfliteFfiInit();

  late Database db;
  late TransactionDao dao;
  late TransactionRepository repo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // Minimal schema: exactly the columns and tables the DAO touches here.
    await db.execute('''
      CREATE TABLE transactions (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        type             TEXT    NOT NULL,
        amount           INTEGER NOT NULL,
        occurred_at      INTEGER NOT NULL,
        description      TEXT    NOT NULL DEFAULT '',
        counterparty     TEXT,
        category_id      TEXT,
        source           TEXT    NOT NULL DEFAULT 'manual',
        account_id       TEXT,
        reference_number TEXT,
        raw_text         TEXT,
        created_at       INTEGER NOT NULL,
        pending_review   INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_tx_reference
        ON transactions (reference_number)
        WHERE reference_number IS NOT NULL
    ''');
    await db.execute('''
      CREATE TABLE suppressed_references (
        reference_number TEXT PRIMARY KEY,
        deleted_at       INTEGER NOT NULL
      )
    ''');
    dao = TransactionDao(db: db);
    repo = TransactionRepository(dao: dao);
  });

  tearDown(() async {
    await db.close();
  });

  Transaction sepayRow({String key = 'sepay:1'}) => Transaction(
        id: Transaction.draftId,
        type: TxType.expense,
        amount: 55000,
        occurredAt: DateTime(2026, 11, 10, 9, 30),
        description: 'GRAB VIETNAM',
        source: TxSource.sepay,
        referenceNumber: key,
        createdAt: DateTime(2026, 11, 10, 9, 30),
      );

  Future<int> countRows() async {
    final List<Map<String, Object?>> rows =
        await db.rawQuery('SELECT COUNT(*) AS c FROM transactions');
    return (rows.first['c']! as num).toInt();
  }

  test('deleting a bank row keeps it deleted across a re-sync', () async {
    // 1. First sync inserts the row.
    final int added = await dao.insertAllIfNew(<Transaction>[sepayRow()]);
    expect(added, 1);
    expect(await countRows(), 1);

    // 2. User deletes it for good.
    final Transaction stored =
        Transaction.fromMap((await db.query('transactions')).first);
    await repo.delete(stored);
    expect(await countRows(), 0);

    // 3. The next sync re-fetches the same reference inside the 3-day overlap.
    final int addedAgain = await dao.insertAllIfNew(<Transaction>[sepayRow()]);
    expect(addedAgain, 0, reason: 'tombstone must block re-insertion');
    expect(await countRows(), 0);
  });

  test('the tombstone also blocks the single-row insert path', () async {
    await dao.insertAllIfNew(<Transaction>[sepayRow(key: 'sepay:7')]);
    final Transaction stored =
        Transaction.fromMap((await db.query('transactions')).first);
    await repo.delete(stored);

    final int id = await dao.insert(sepayRow(key: 'sepay:7'));
    expect(id, 0);
    expect(await countRows(), 0);
  });

  test('deleting a manual row leaves no tombstone and frees the slot',
      () async {
    final Transaction manual = Transaction(
      id: Transaction.draftId,
      type: TxType.expense,
      amount: 20000,
      occurredAt: DateTime(2026, 11, 10, 12),
      description: 'Cà phê',
      createdAt: DateTime(2026, 11, 10, 12),
    );
    final int id = await dao.insert(manual);
    await repo.delete(manual.copyWith(id: id));

    expect(await countRows(), 0);
    expect(await dao.suppressedReferences(), isEmpty);
  });

  test('other references are unaffected by a tombstone', () async {
    await dao.insertAllIfNew(<Transaction>[sepayRow(key: 'sepay:1')]);
    final Transaction stored =
        Transaction.fromMap((await db.query('transactions')).first);
    await repo.delete(stored);

    final int added = await dao.insertAllIfNew(
      <Transaction>[sepayRow(key: 'sepay:2')],
    );
    expect(added, 1);
    expect(await dao.suppressedReferences(), <String>{'sepay:1'});
  });
}
