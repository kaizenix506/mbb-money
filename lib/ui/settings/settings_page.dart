import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories/secret_store.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/sync_service.dart';
import '../../data/services/notification_service.dart';
import '../stores/transaction_store.dart';
import '../widgets/common.dart';

/// Cyberpunk Settings Screen:
/// - 100% focused on SePay API Token (Shortcut feature stripped completely)
/// - Pure EXPENSE tracking configuration
/// - Custom AI API Key setup (for Cyber AI Chatbot)
/// - Clean 1-touch SePay Token setup
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static const String route = '/settings';

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _tokenCtrl = TextEditingController();
  final TextEditingController _accountCtrl = TextEditingController();
  final TextEditingController _geminiCtrl = TextEditingController();

  bool _busy = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _accountCtrl.dispose();
    _geminiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsRepository settings = context.watch<SettingsRepository>();
    final SecretStore secrets = context.watch<SecretStore>();

    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'SEPAY & CẤU HÌNH HỆ THỐNG',
          style: TextStyle(
            fontFamily: 'Courier New',
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: AppColors.neonCyan,
            letterSpacing: 1.2,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.neonCyan, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: <Widget>[
          // Section 1: SePay MB Bank Integration
          _SectionTitle('ĐỒNG BỘ SEPAY (MB BANK)'),
          _CyberSepayCard(
            settings: settings,
            secrets: secrets,
            tokenController: _tokenCtrl,
            accountController: _accountCtrl,
            busy: _busy,
            testResult: _testResult,
            testOk: _testOk,
            onSaveToken: _saveToken,
            onClearToken: _clearToken,
            onTest: () => _testConnection(secrets),
            onSyncNow: _syncNow,
          ),
          const SizedBox(height: 24),

          // Section 2: AI Neural Engine Key (Optional)
          _SectionTitle('A.R.I.A CYBER AI NEURAL CORE'),
          _CyberAiConfigCard(controller: _geminiCtrl),
          const SizedBox(height: 24),

          // Section 3: Notifications
          _SectionTitle('NHẮC NHỞ BIẾN ĐỘNG SỐ DƯ'),
          _CyberNotificationsCard(settings: settings),
          const SizedBox(height: 24),

          // Section 4: Data Management
          _SectionTitle('DỮ LIỆU & BỘ NHỚ LOCAL'),
          _CyberDataCard(),
        ],
      ),
    );
  }

  Future<void> _saveToken() async {
    final String token = _tokenCtrl.text.trim();
    if (token.isEmpty) return;

    setState(() => _busy = true);
    final SecretStore secrets = context.read<SecretStore>();
    final SettingsRepository settings = context.read<SettingsRepository>();

    await secrets.saveSepayToken(token);
    await settings.setEnabled(DataSource.sepay, true);

    final String account = _accountCtrl.text.trim();
    if (account.isNotEmpty) {
      await settings.setSepayAccountNumber(account);
    }

    if (!mounted) return;
    _tokenCtrl.clear();
    setState(() => _busy = false);
    _snack('Đã liên kết SePay thành công vào máy!');
  }

  Future<void> _clearToken() async {
    await context.read<SecretStore>().clearSepayToken();
    if (!mounted) return;
    _snack('Đã ngắt kết nối SePay');
  }

  Future<void> _testConnection(SecretStore secrets) async {
    final String? token = await secrets.readSepayToken();
    if (token == null || token.isEmpty) {
      _snack('Chưa nhập hoặc chưa lưu token');
      return;
    }

    setState(() {
      _busy = true;
      _testResult = null;
    });

    final SyncReport report = await context.read<SyncService>().testConnection(token);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _testOk = report.ok;
      _testResult = report.ok
          ? 'Kết nối MB Bank qua SePay hoàn hảo!'
          : 'Lỗi: ${report.error}';
    });
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    final SettingsRepository settings = context.read<SettingsRepository>();
    final SyncService sync = context.read<SyncService>();
    final SyncReport report = await sync.syncSepay(
      accountNumber: settings.sepayAccountNumber,
    );
    if (report.added > 0) {
      await settings.markSynced(DateTime.now());
      if (mounted) {
        await context.read<TransactionStore>().afterExternalIngest();
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(SyncService.describe(report));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.panel,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Courier New',
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: AppColors.neonCyan,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _CyberSepayCard extends StatelessWidget {
  const _CyberSepayCard({
    required this.settings,
    required this.secrets,
    required this.tokenController,
    required this.accountController,
    required this.busy,
    required this.testResult,
    required this.testOk,
    required this.onSaveToken,
    required this.onClearToken,
    required this.onTest,
    required this.onSyncNow,
  });

  final SettingsRepository settings;
  final SecretStore secrets;
  final TextEditingController tokenController;
  final TextEditingController accountController;
  final bool busy;
  final String? testResult;
  final bool testOk;
  final VoidCallback onSaveToken;
  final VoidCallback onClearToken;
  final VoidCallback onTest;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final bool hasToken = secrets.hasSepayToken;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: hasToken
              ? AppColors.neonCyan.withValues(alpha: 0.6)
              : AppColors.neonPink.withValues(alpha: 0.4),
        ),
        boxShadow: AppColors.neonGlow(hasToken ? AppColors.neonCyan : AppColors.neonPink, blur: 14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.neonCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.neonCyan),
                ),
                child: const Icon(Icons.bolt, color: AppColors.neonCyan, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SePay API Token',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      hasToken ? 'Đang kích hoạt đồng bộ MB Bank' : 'Chưa có Token SePay',
                      style: TextStyle(
                        fontSize: 12,
                        color: hasToken ? AppColors.neonGreen : AppColors.neonPink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasToken)
                IconButton(
                  icon: const Icon(Icons.sync_rounded, color: AppColors.neonCyan),
                  tooltip: 'Đồng bộ ngay',
                  onPressed: busy ? null : onSyncNow,
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Chỉ cần tạo 1 Token API miễn phí tại my.sepay.vn (mục API Access) và dán vào đây. App sẽ tự động kéo các khoản tiền chuyển đi (chi tiêu) của MB Bank về điện thoại của bạn.',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkDim, height: 1.4),
          ),
          const SizedBox(height: 16),

          if (hasToken) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bgTop,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TOKEN: ${secrets.maskedSepayToken}',
                    style: const TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.neonCyan,
                    ),
                  ),
                  TextButton(
                    onPressed: onClearToken,
                    child: const Text('Xoá', style: TextStyle(color: AppColors.neonPink, fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onTest,
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Kiểm tra kết nối'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.neonCyan,
                      side: const BorderSide(color: AppColors.neonCyan),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onSyncNow,
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Kéo giao dịch'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.neonCyan,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            TextField(
              controller: tokenController,
              obscureText: true,
              style: const TextStyle(color: AppColors.ink, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Dán SePay API Token vào đây...',
                hintStyle: const TextStyle(color: AppColors.inkFaint, fontSize: 12),
                filled: true,
                fillColor: AppColors.bgTop,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.stroke),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.neonCyan),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: accountController,
              style: const TextStyle(color: AppColors.ink, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Số tài khoản MB Bank (tuỳ chọn)',
                hintStyle: const TextStyle(color: AppColors.inkFaint, fontSize: 12),
                filled: true,
                fillColor: AppColors.bgTop,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.stroke),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onSaveToken,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.neonCyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text(
                        'LƯU VÀ KÍCH HOẠT SEPAY',
                        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0),
                      ),
              ),
            ),
          ],

          if (testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: testOk
                    ? AppColors.neonGreen.withValues(alpha: 0.1)
                    : AppColors.neonPink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: testOk ? AppColors.neonGreen : AppColors.neonPink),
              ),
              child: Text(
                testResult!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: testOk ? AppColors.neonGreen : AppColors.neonPink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CyberAiConfigCard extends StatelessWidget {
  const _CyberAiConfigCard({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.neonViolet.withValues(alpha: 0.5)),
        boxShadow: AppColors.neonGlow(AppColors.neonViolet, blur: 14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.neonViolet.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.neonViolet),
                ),
                child: const Icon(Icons.psychology, color: AppColors.neonViolet, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trợ lý ảo A.R.I.A 2077',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                    ),
                    Text(
                      'AI phân tích chi tiêu & cố vấn tài chính',
                      style: TextStyle(fontSize: 12, color: AppColors.neonViolet),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Mặc định A.R.I.A chạy bằng thuật toán tài chính ngoại tuyến siêu nhanh trên máy (100% offline). Nếu muốn dùng mô hình ngôn ngữ lớn (Gemini), bạn có thể nhập Gemini API Key miễn phí dưới đây.',
            style: TextStyle(fontSize: 12, color: AppColors.inkDim, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            obscureText: true,
            style: const TextStyle(color: AppColors.ink, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Nhập Gemini API Key (tuỳ chọn)...',
              hintStyle: const TextStyle(color: AppColors.inkFaint, fontSize: 12),
              filled: true,
              fillColor: AppColors.bgTop,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.stroke),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: () async {
                final key = controller.text.trim();
                await context.read<SecretStore>().saveGeminiApiKey(key);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã cập nhật AI Key!')),
                  );
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.neonViolet,
                side: const BorderSide(color: AppColors.neonViolet),
              ),
              child: const Text('Lưu AI Key'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Toggles the "biến động số dư" reminders and shows whether the background
/// worker is currently polling SePay.
class _CyberNotificationsCard extends StatelessWidget {
  const _CyberNotificationsCard({required this.settings});

  final SettingsRepository settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        color: AppColors.glassPanel,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.balanceAlertsEnabled,
            activeTrackColor: AppColors.neonCyan.withValues(alpha: 0.35),
            title: const Text(
              'Nhắc phân loại khi số dư đổi',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            subtitle: const Text(
              'Có giao dịch mới, app sẽ nhắc bạn thêm danh mục và mô tả.',
              style: TextStyle(fontSize: 11.5, color: AppColors.inkDim),
            ),
            onChanged: (bool v) async {
              await settings.setBalanceAlerts(v);
              if (v) await NotificationService.instance.ensurePermission();
            },
          ),
          const Divider(color: AppColors.strokeFaint, height: 22),
          Row(
            children: <Widget>[
              Icon(
                Icons.sync_rounded,
                size: 15,
                color: settings.sepayEnabled
                    ? AppColors.neonGreen
                    : AppColors.inkFaint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  settings.sepayEnabled
                      ? 'Đồng bộ nền đang bật · quét mỗi 45 giây'
                      : 'Đồng bộ nền đang tắt',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.inkDim,
                  ),
                ),
              ),
              if (settings.lastSyncAt != null)
                Text(
                  Fmt.time(settings.lastSyncAt!),
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 11,
                    color: AppColors.inkFaint,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CyberDataCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BẢO MẬT & BỘ NHỚ SQLITE OFFLINE',
            style: TextStyle(
              fontFamily: 'Courier New',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Toàn bộ lịch sử chi tiêu MB Bank được mã hoá và lưu trực tiếp trên iPhone qua SQLite. Không có máy chủ trung gian nào theo dõi số dư của bạn.',
            style: TextStyle(fontSize: 12, color: AppColors.inkDim, height: 1.4),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () {
              context.read<TransactionStore>().refresh();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã làm mới dữ liệu từ SQLite!')),
              );
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Làm mới bộ nhớ đệm'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.inkDim,
              side: const BorderSide(color: AppColors.stroke),
            ),
          ),
        ],
      ),
    );
  }
}
