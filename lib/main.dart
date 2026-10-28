import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import 'app.dart';
import 'data/db/database.dart';
import 'data/db/transaction_dao.dart';
import 'data/db/wishlist_dao.dart';
import 'data/models/transaction.dart';
import 'data/repositories/secret_store.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/sync_service.dart';
import 'data/repositories/transaction_repository.dart';
import 'data/services/background_sync_service.dart';
import 'data/services/cyber_ai_service.dart';
import 'data/services/new_transaction_watcher.dart';
import 'data/services/notification_service.dart';
import 'data/services/webhook_ingest_service.dart';
import 'data/stores/category_store.dart';
import 'data/stores/wishlist_store.dart';
import 'ui/stores/transaction_store.dart';

/// Where the SQLite file lives.
///
/// Empty string means "let sqflite resolve it" (iOS/Android). On desktop we
/// must supply an absolute path because the FFI factory has no databases dir.
String _dbDirectory = '';

/// Test seam: lets tests point AppDatabase at an in-memory database.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_needsFfi()) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final Directory support = await getApplicationSupportDirectory();
    _dbDirectory = p.join(support.path, 'db');
    await Directory(_dbDirectory).create(recursive: true);
  }

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0C11),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final SettingsRepository settings = SettingsRepository(prefs);
  final SecretStore secrets = SecretStore();
  await secrets.load();

  final TransactionDao dao = TransactionDao(directory: _dbDirectory);
  final TransactionRepository repo = TransactionRepository(dao: dao);
  final SyncService sync = SyncService(secrets: secrets, transactions: repo);
  final TransactionStore store = TransactionStore(repo);

  final DeepLinkHandler links = DeepLinkHandler(store, repo);
  unawaited(store.load());
  unawaited(links.start());

  final CyberAiService ai = CyberAiService(secrets: secrets);
  final CategoryStore categories = CategoryStore();
  final WishlistDao wishlistDao =
      WishlistDao(AppDatabase.instance.databaseIn(_dbDirectory));
  final WishlistStore wishlistStore = WishlistStore(dao: wishlistDao);

  // Worker + notifications: both are best-effort. A failure here must never
  // block the first frame, so they are fired without awaiting.
  final NotificationService notifications = NotificationService.instance;
  unawaited(notifications.init());

  // One watcher instance for the whole app: the background worker, the
  // overview poll and the resume hook all call into it, so a row is announced
  // exactly once no matter which path noticed it first.
  final NewTransactionWatcher watcher = NewTransactionWatcher(dao: dao);
  unawaited(watcher.seedIfNeeded());

  final WebhookIngestService webhook = WebhookIngestService(
    secrets: secrets,
    settings: settings,
    transactions: repo,
  );

  final BackgroundSyncService worker = BackgroundSyncService(
    sync: sync,
    secrets: secrets,
    settings: settings,
    repository: repo,
    dao: dao,
    webhook: webhook,
    watcher: watcher,
  );
  unawaited(worker.start());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsRepository>.value(value: settings),
        ChangeNotifierProvider<SecretStore>.value(value: secrets),
        ChangeNotifierProvider<TransactionStore>.value(value: store),
        ChangeNotifierProvider<CategoryStore>.value(value: categories),
        ChangeNotifierProvider<WishlistStore>.value(value: wishlistStore),
        ChangeNotifierProvider<CyberAiService>.value(value: ai),
        Provider<TransactionRepository>.value(value: repo),
        Provider<SyncService>.value(value: sync),
        Provider<DeepLinkHandler>.value(value: links),
        Provider<BackgroundSyncService>.value(value: worker),
        Provider<WebhookIngestService>.value(value: webhook),
        Provider<NewTransactionWatcher>.value(value: watcher),
      ],
      child: const MbbMoneyApp(),
    ),
  );
}

bool _needsFfi() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

/// Bridges `app_links` to the transaction repository.
///
/// Lives outside the widget tree so a link that launches the app during a cold
/// start is not lost while the first frame is still being built.
class DeepLinkHandler {
  DeepLinkHandler(this._store, this._repo);

  final TransactionStore _store;
  final TransactionRepository _repo;
  final AppLinks _links = AppLinks();

  StreamSubscription<Uri>? _sub;

  /// Populated by the app root so handlers can surface a SnackBar.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  Future<void> start() async {
    try {
      final Uri? initial = await _links.getInitialLink();
      if (initial != null) await _handle(initial);

      _sub = _links.uriLinkStream.listen(
        (Uri uri) => unawaited(_handle(uri)),
        onError: (Object e) => debugPrint('deep link error: $e'),
      );
    } on Object catch (e) {
      // Platform channels are unavailable when the app runs in a unit test.
      debugPrint('deep link listener unavailable: $e');
    }
  }

  Future<void> dispose() => _sub?.cancel() ?? Future<void>.value();

  Future<void> _handle(Uri uri) async {
    if (uri.scheme != 'mbbmoney') return;

    final String raw = uri.queryParameters['raw'] ?? '';
    final IngestResult result;

    if (raw.isNotEmpty) {
      result = await _repo.ingestRawText(raw, receivedAt: DateTime.now());
    } else {
      // Fallback shape for a hand-built Shortcut:
      //   mbbmoney://add?amount=58000&desc=Grab
      final int amount =
          int.tryParse(uri.queryParameters['amount'] ?? '') ?? 0;
      if (amount <= 0) return;
      final bool isIncome = uri.queryParameters['type'] == 'income';
      final Transaction tx = await _repo.addManual(
        type: isIncome ? TxType.income : TxType.expense,
        amount: amount,
        occurredAt: DateTime.now(),
        description: uri.queryParameters['desc'] ?? 'Từ MB Bank',
      );
      result = IngestResult(IngestStatus.added, transaction: tx);
    }

    // Re-opening the same SMS or a non-bank message must be silent: the
    // automation runs on every incoming text.
    if (result.status != IngestStatus.added &&
        result.status != IngestStatus.needsReview &&
        result.status != IngestStatus.failed) {
      return;
    }

    await _store.afterExternalIngest();

    final String message = switch (result.status) {
      IngestStatus.added =>
        'Đã ghi: ${result.transaction?.description ?? 'giao dịch'}',
      IngestStatus.needsReview => 'Đã ghi · cần xác nhận phân loại',
      IngestStatus.failed => 'Không đọc được tin nhắn',
      IngestStatus.duplicate || IngestStatus.ignored => '',
    };
    if (message.isEmpty) return;

    messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
    await HapticFeedback.lightImpact();
  }
}
