import 'package:flutter/material.dart';

/// Reusable utility and container for modal bottom sheets in EasyConnect.
/// Ensures consistent edge-to-edge aesthetics while guaranteeing that all
/// bottom content and interactive elements are safely elevated above Android's
/// 3-button navigation bar (48-56dp) and gesture bar (16-20dp).
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool enableDrag = true,
  bool isDismissible = true,
  Color backgroundColor = Colors.transparent,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    isDismissible: isDismissible,
    backgroundColor: backgroundColor,
    builder: builder,
  );
}

/// A container widget for bottom sheets that draws a seamless background
/// down to the physical screen edge while strictly safeguarding all content
/// and buttons with [SafeArea] and custom bottom padding.
class AppBottomSheetContainer extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool showDragHandle;

  const AppBottomSheetContainer({
    super.key,
    required this.child,
    this.backgroundColor,
    this.borderRadius = 24.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
    this.showDragHandle = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? (theme.brightness == Brightness.dark ? const Color(0xFF1E1B4B) : Colors.white);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDragHandle) ...[
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16.0),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
