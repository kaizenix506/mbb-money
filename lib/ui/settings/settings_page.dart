import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories/secret_store.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/sync_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/webhook_ingest_service.dart';
import '../stores/transaction_store.dart';

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final SecretStore secrets = context.read<SecretStore>();
      final String key = await secrets.readGeminiApiKey();
      if (mounted && key.isNotEmpty && _geminiCtrl.text.isEmpty) {
        setState(() {
          _geminiCtrl.text = key;
        });
      }
    });
  }

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
          const _SectionTitle('ĐỒNG BỘ SEPAY (MB BANK)'),
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
          const _SectionTitle('A.R.I.A CYBER AI NEURAL CORE'),
          _CyberAiConfigCard(controller: _geminiCtrl),
          const SizedBox(height: 24),

          // Section 3: Notifications
          const _SectionTitle('NHẮC NHỞ BIẾN ĐỘNG SỐ DƯ'),
          _CyberNotificationsCard(settings: settings),
          const SizedBox(height: 24),

          // Section 4: Webhook relay — the always-on ingest path.
          const _SectionTitle('WEBHOOK TỨC THÌ (KHI APP ĐÃ TẮT)'),
          const _CyberWebhookCard(),
          const SizedBox(height: 24),

          // Section 5: Data Management
          const _SectionTitle('DỮ LIỆU & BỘ NHỚ LOCAL'),
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

class _CyberAiConfigCard extends StatefulWidget {
  const _CyberAiConfigCard({required this.controller});
  final TextEditingController controller;

  @override
  State<_CyberAiConfigCard> createState() => _CyberAiConfigCardState();
}

class _CyberAiConfigCardState extends State<_CyberAiConfigCard> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final SecretStore secrets = context.watch<SecretStore>();
    final bool hasKey = secrets.hasGeminiApiKey;

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
                child: const Icon(Icons.psychology,
                    color: AppColors.neonViolet, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trợ lý ảo A.R.I.A 2077',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink),
                    ),
                    Text(
                      'AI phân tích chi tiêu & cố vấn tài chính',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.neonViolet),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'A.R.I.A sử dụng mô hình Gemini xử lý ngôn ngữ tự nhiên để tự động bắt số tiền, chọn danh mục và tư vấn tài chính. Key của bạn được lưu mã hóa an toàn trên thiết bị.',
            style:
                TextStyle(fontSize: 12, color: AppColors.inkDim, height: 1.4),
          ),
          const SizedBox(height: 10),

          // Active model indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x6604060C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.strokeFaint),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.neonYellow, size: 14),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Model đang dùng: Gemini 3.5 Flash Lite (Tốc độ cao)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.neonYellow,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          if (hasKey)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.neonGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.neonGreen, width: 0.8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.neonGreen, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'ĐÃ LƯU AI KEY: ${secrets.maskedGeminiApiKey}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.neonGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          TextField(
            controller: widget.controller,
            obscureText: _obscure,
            style: const TextStyle(
                color: AppColors.ink,
                fontSize: 13,
                fontFamily: 'Courier New'),
            decoration: InputDecoration(
              labelText: 'Gemini API Key',
              labelStyle: const TextStyle(color: AppColors.neonViolet),
              hintText: 'Nhập Gemini API Key...',
              hintStyle:
                  const TextStyle(color: AppColors.inkFaint, fontSize: 12),
              filled: true,
              fillColor: AppColors.bgTop,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.neonViolet,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.stroke),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () async {
                  await secrets.clearGeminiApiKey();
                  widget.controller.clear();
                  final key = await secrets.readGeminiApiKey();
                  widget.controller.text = key;
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Đã đặt lại AI Key mặc định!')),
                    );
                  }
                },
                child: const Text('Đặt lại mặc định',
                    style: TextStyle(color: AppColors.inkFaint, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final key = widget.controller.text.trim();
                  await secrets.saveGeminiApiKey(key);
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
            ],
          ),
        ],
      ),
    );
  }
}

/// Server-side relay configuration.
///
/// Explains itself in-place because the concept is not obvious: iOS cannot keep
/// the app listening for a bank push, so SePay pushes to a Worker and the app
/// drains that Worker's inbox on every start.
class _CyberWebhookCard extends StatefulWidget {
  const _CyberWebhookCard();

  @override
  State<_CyberWebhookCard> createState() => _CyberWebhookCardState();
}

class _CyberWebhookCardState extends State<_CyberWebhookCard> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  bool _busy = false;
  String? _result;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    final SettingsRepository settings = context.read<SettingsRepository>();
    _url = TextEditingController(text: settings.webhookUrl ?? '');
    _token = TextEditingController();
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final SettingsRepository settings = context.read<SettingsRepository>();
    final SecretStore secrets = context.read<SecretStore>();

    await settings.setWebhookUrl(_url.text);
    if (_token.text.trim().isNotEmpty) {
      await secrets.saveWebhookPullToken(_token.text);
      _token.clear();
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = true;
      _result = 'Đã lưu. Webhook sẽ được kéo mỗi lần app mở.';
    });
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final SettingsRepository settings = context.read<SettingsRepository>();
    final SecretStore secrets = context.read<SecretStore>();

    await settings.setWebhookUrl(_url.text);
    if (_token.text.trim().isNotEmpty) {
      await secrets.saveWebhookPullToken(_token.text);
      _token.clear();
    }

    final WebhookIngestService svc = context.read<WebhookIngestService>();
    final WebhookPullReport report = await svc.pull();

    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = report.ok;
      _result = report.ok
          ? (report.isEmpty
              ? 'Kết nối OK · hộp thư trống'
              : 'Kết nối OK · nhận ${report.received}, thêm ${report.added}')
          : report.error;
    });

    if (report.added > 0 && mounted) {
      await context.read<TransactionStore>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettingsRepository settings = context.watch<SettingsRepository>();
    final bool configured = settings.webhookUrl != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        color: AppColors.glassPanel,
        border: Border.all(
          color: configured ? AppColors.neonGreen : AppColors.glassBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                configured
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                size: 16,
                color: configured ? AppColors.neonGreen : AppColors.inkFaint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  configured
                      ? 'ĐANG DÙNG WEBHOOK'
                      : 'CHƯA CẤU HÌNH WEBHOOK',
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: configured ? AppColors.neonGreen : AppColors.inkFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'iOS không cho app nghe ngân hàng khi đã đóng. SePay sẽ đẩy giao dịch '
            'sang một endpoint luôn thức, app chỉ việc kéo về khi mở lên — '
            'nhờ vậy không mất khoản nào.',
            style: TextStyle(fontSize: 11.5, height: 1.45, color: AppColors.inkDim),
          ),
          const SizedBox(height: 14),
          _WebhookField(
            controller: _url,
            label: 'Địa chỉ Worker',
            hint: 'https://mbb-money-webhook.xxx.workers.dev',
          ),
          const SizedBox(height: 10),
          _WebhookField(
            controller: _token,
            label: 'Pull token',
            hint: configured ? 'Đã lưu · nhập lại để đổi' : 'APP_PULL_TOKEN',
            obscure: true,
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _test,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.neonCyan,
                    side: const BorderSide(color: AppColors.neonCyan),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  child: const Text('Kiểm tra', style: TextStyle(fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.neonCyan,
                    foregroundColor: const Color(0xFF04231A),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF04231A),
                          ),
                        )
                      : const Text('Lưu', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
          ),
          if (_result != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _result!,
              style: TextStyle(
                fontSize: 11.5,
                color: _ok ? AppColors.neonGreen : AppColors.coral,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WebhookField extends StatelessWidget {
  const _WebhookField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontSize: 11.5, color: AppColors.inkDim),
        hintStyle: const TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.neonCyan),
        ),
      ),
    );
  }
}

/// Toggles the "biến động số dư" reminders and shows whether the background
/// worker is currently polling SePay.
class _CyberNotificationsCard extends StatefulWidget {
  const _CyberNotificationsCard({required this.settings});

  final SettingsRepository settings;

  @override
  State<_CyberNotificationsCard> createState() =>
      _CyberNotificationsCardState();
}

class _CyberNotificationsCardState extends State<_CyberNotificationsCard> {
  /// Whether the OS will actually deliver a banner right now. Read on mount and
  /// after each attempt, so a permission revoked in iOS Settings is visible
  /// here instead of silently swallowing reminders.
  bool _notifGranted = false;
  bool _testingNotif = false;

  SettingsRepository get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final bool ok = await NotificationService.instance.hasPermission();
    if (mounted) setState(() => _notifGranted = ok);
  }

  /// Sends one real banner so Hoàng can confirm the chain end-to-end. Asks for
  /// permission first if it was never granted, and reports back if the user
  /// keeps it off — otherwise the button looks broken.
  Future<void> _testNotification() async {
    setState(() => _testingNotif = true);
    final bool ok = await NotificationService.instance.ensurePermission();
    if (ok) {
      await NotificationService.instance.notifyNewTransactions(
        newCount: 1,
        unclassifiedTotal: 45000,
        samples: const <String>['Thử nhắc · Highlands Coffee'],
      );
    }
    if (!mounted) return;
    setState(() {
      _testingNotif = false;
      _notifGranted = ok;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'iOS chưa cho phép thông báo. Mở Cài đặt › MBB Money › Thông báo để bật.',
          ),
        ),
      );
    }
  }

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
          if (settings.balanceAlertsEnabled) ...<Widget>[
            const SizedBox(height: 4),
            // A reminder that silently does nothing is worse than no reminder:
            // this row shows the actual permission state and lets Hoàng prove
            // to himself that the banner reaches the lock screen.
            Row(
              children: <Widget>[
                const Icon(Icons.notifications_active_rounded,
                    size: 15, color: AppColors.inkDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _notifGranted
                        ? 'Quyền thông báo: đã bật'
                        : 'Quyền thông báo: chưa bật',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _notifGranted
                          ? AppColors.neonGreen
                          : AppColors.neonYellow,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _testingNotif ? null : _testNotification,
                  child: Text(_testingNotif ? 'Đang gửi…' : 'Thử nhắc'),
                ),
              ],
            ),
          ],
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
