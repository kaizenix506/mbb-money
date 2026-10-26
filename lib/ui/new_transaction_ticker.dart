import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../data/services/new_transaction_watcher.dart';

/// Keeps the "new transaction needs a category" check ticking while the app is
/// in the foreground.
///
/// Why this exists on top of the background worker: iOS only lets a periodic
/// timer run while the app is actually on screen, so an app left open on the
/// overview would otherwise never re-check the ledger and Hoàng only saw the
/// reminder after opening a specific screen. This widget turns that into "the
/// banner arrives on its own".
///
/// It is deliberately cheap: a single indexed `MAX(id)` read per tick, and the
/// timer is paused whenever the app leaves the foreground so it does not keep
/// the CPU awake.
class NewTransactionTicker extends StatefulWidget {
  const NewTransactionTicker({required this.child, super.key});

  final Widget child;

  /// 20 s rides alongside the 45 s SePay poll: fast enough to feel immediate,
  /// slow enough that the DB read is noise.
  static const Duration interval = Duration(seconds: 20);

  @override
  State<NewTransactionTicker> createState() => _NewTransactionTickerState();
}

class _NewTransactionTickerState extends State<NewTransactionTicker>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Let the first frame land before touching the database.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
      _tick();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _start() {
    if (!mounted || (_timer?.isActive ?? false)) return;
    _timer = Timer.periodic(NewTransactionTicker.interval, (_) => _tick());
    _tick();
  }

  Future<void> _tick() async {
    if (!mounted) return;
    final NewTransactionWatcher? watcher =
        Provider.of<NewTransactionWatcher?>(context, listen: false);
    if (watcher == null) return;
    await watcher.checkAndNotify();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
