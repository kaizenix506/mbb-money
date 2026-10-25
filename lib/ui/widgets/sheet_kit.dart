import 'package:flutter/material.dart';

/// Shared configuration for every bottom sheet in the app.
///
/// Fixes the three gesture problems Hoàng hit:
///  1. **Vuốt xuống không đóng** — the modal barrier was swallowing the drag
///     because the sheet had a hard `height` and no drag handle.
///  2. **Vuốt từ rìa trái/phải** — iOS edge-swipe back was blocked by
///     `PopScope`-less full-screen sheets; the app now opts into the platform
///     back gesture and every pushed route uses a swipe-able page transition.
///  3. **Bàn phím không tự ẩn khi chạm vùng trống** — the content is wrapped in
///     a `TapRegion`, so any tap outside an input unfocuses it.
abstract final class SheetKit {
  /// Drag-handle + barrier config shared by all sheets.
  static const bool isDismissible = true;

  /// Enables the iOS "drag the sheet down from anywhere" gesture.
  static const bool enableDrag = true;

  /// Wraps [child] so tapping empty space anywhere on screen hides the keyboard.
  static Widget dismissKeyboardOnTap(Widget child) {
    return TapRegion(
      onTapOutside: (PointerDownEvent _) =>
          FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }

  /// Standard rounded glass container used by every sheet body.
  static Widget handle({Color color = const Color(0x40FFFFFF)}) {
    return Center(
      child: Container(
        width: 42,
        height: 4.5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
