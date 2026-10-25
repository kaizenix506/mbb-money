import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/vn_clock.dart';
import '../../data/repositories/settings_repository.dart';
import '../widgets/cyber_avatar.dart';

/// Top-of-overview header: avatar, greeting and a **live** UTC+7 clock.
///
/// The clock is driven by [TickerClock] so the seconds actually move while the
/// screen is open, and every field is computed in Vietnam time regardless of
/// the device timezone.
class LiveHeader extends StatelessWidget {
  const LiveHeader({
    required this.clock,
    required this.onOpenSettings,
    required this.onOpenCategories,
    super.key,
  });

  final TickerClock clock;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenCategories;

  @override
  Widget build(BuildContext context) {
    final SettingsRepository settings = context.watch<SettingsRepository>();
    final String name = settings.displayName;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              CyberAvatar(
                name: name,
                imagePath: settings.avatarPath,
                onTap: () => _editAvatar(context, settings),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '${VnClock.greeting}, $name',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.neonCyan,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        Text(
                          VnClock.weekdayLabel(clock.now),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.3,
                            color: AppColors.inkFaint,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          VnClock.dateLabel(clock.now),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkDim,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _HeaderIconButton(
                icon: Icons.category_rounded,
                label: 'Danh mục',
                onTap: onOpenCategories,
              ),
              const SizedBox(width: 8),
              _HeaderIconButton(
                icon: Icons.tune_rounded,
                label: 'Cài đặt',
                onTap: onOpenSettings,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _LiveClockStrip(clock: clock),
        ],
      ),
    );
  }

  Future<void> _editAvatar(
    BuildContext context,
    SettingsRepository settings,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      builder: (BuildContext sheetCtx) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: BoxDecoration(
            color: AppColors.bgMid,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              CyberAvatar(
                name: settings.displayName,
                imagePath: settings.avatarPath,
                size: 84,
              ),
              const SizedBox(height: 18),
              _AvatarAction(
                icon: Icons.photo_library_rounded,
                label: 'Chọn ảnh từ thư viện',
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  final XFile? picked = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 600,
                    imageQuality: 88,
                  );
                  if (picked == null) return;
                  await settings.setAvatarPath(picked.path);
                },
              ),
              const SizedBox(height: 10),
              _AvatarAction(
                icon: Icons.photo_camera_rounded,
                label: 'Chụp ảnh mới',
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  final XFile? picked = await ImagePicker().pickImage(
                    source: ImageSource.camera,
                    maxWidth: 600,
                    imageQuality: 88,
                  );
                  if (picked == null) return;
                  await settings.setAvatarPath(picked.path);
                },
              ),
              const SizedBox(height: 10),
              _AvatarAction(
                icon: Icons.abc_rounded,
                label: 'Đổi tên hiển thị',
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  await _renameSelf(context, settings);
                },
              ),
              if (settings.avatarPath != null) ...<Widget>[
                const SizedBox(height: 10),
                _AvatarAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'Xoá ảnh, dùng chữ cái',
                  danger: true,
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    await settings.setAvatarPath(null);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _renameSelf(
    BuildContext context,
    SettingsRepository settings,
  ) async {
    final TextEditingController ctrl =
        TextEditingController(text: settings.displayName);
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: const Text('Tên hiển thị', style: TextStyle(color: AppColors.ink)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.ink),
          decoration: const InputDecoration(hintText: 'Ví dụ: Hoàng'),
          onSubmitted: (String v) => Navigator.of(ctx).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value != null) await settings.setDisplayName(value);
  }
}

/// Monospace ticker showing the UTC+7 time with seconds.
class _LiveClockStrip extends StatelessWidget {
  const _LiveClockStrip({required this.clock});

  final TickerClock clock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.clockStrip,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.neonGreen,
              boxShadow: AppColors.neonGlow(AppColors.neonGreen, blur: 7),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'GIỜ VIỆT NAM',
            style: TextStyle(
              fontFamily: 'Courier New',
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: AppColors.inkFaint,
            ),
          ),
          const Spacer(),
          Text(
            clock.hms,
            style: const TextStyle(
              fontFamily: 'Courier New',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              color: AppColors.neonCyan,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'UTC+7',
            style: TextStyle(
              fontFamily: 'Courier New',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: AppColors.strokeFaint),
          ),
          child: Icon(icon, size: 18, color: AppColors.inkDim),
        ),
      ),
    );
  }
}

class _AvatarAction extends StatelessWidget {
  const _AvatarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? AppColors.neonPink : AppColors.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.field),
          color: Colors.white.withValues(alpha: 0.045),
          border: Border.all(color: AppColors.strokeFaint),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Resolves an avatar file, falling back gracefully when the OS evicted it.
Future<File?> resolveAvatarFile(String? path) async {
  if (path == null || path.isEmpty) return null;
  final File f = File(path);
  return f.existsSync() ? f : null;
}
