import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Circular avatar that shows the user's photo when there is one and a glowing
/// monogram otherwise. Both cases share the same neon ring so the header never
/// jumps when the photo is added or removed.
class CyberAvatar extends StatefulWidget {
  const CyberAvatar({
    required this.name,
    this.imagePath,
    this.size = 46,
    this.onTap,
    super.key,
  });

  final String name;
  final String? imagePath;
  final double size;
  final VoidCallback? onTap;

  @override
  State<CyberAvatar> createState() => _CyberAvatarState();
}

class _CyberAvatarState extends State<CyberAvatar> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final String initial = widget.name.trim().isEmpty
        ? 'H'
        : widget.name.trim().characters.first.toUpperCase();

    final File? file = (widget.imagePath != null && widget.imagePath!.isNotEmpty)
        ? File(widget.imagePath!)
        : null;
    final bool hasPhoto = file != null && file.existsSync();

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasPhoto
                    ? null
                    : const RadialGradient(
                        colors: <Color>[AppColors.neonCyan, Color(0xFF0077FF)],
                      ),
                border: Border.all(
                  color: AppColors.neonCyan.withValues(alpha: 0.85),
                  width: 2,
                ),
                boxShadow: AppColors.liquidGlow(AppColors.neonCyan, blur: 14),
                image: hasPhoto
                    ? DecorationImage(
                        image: FileImage(file),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              alignment: Alignment.center,
              child: hasPhoto
                  ? null
                  : Text(
                      initial,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: widget.size * 0.42,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
            ),
            // Little camera dot so it is obvious the avatar is tappable.
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: widget.size * 0.34,
                height: widget.size * 0.34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgMid,
                  border: Border.all(color: AppColors.neonCyan, width: 1.2),
                ),
                child: Icon(
                  Icons.photo_camera_rounded,
                  size: widget.size * 0.18,
                  color: AppColors.neonCyan,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
