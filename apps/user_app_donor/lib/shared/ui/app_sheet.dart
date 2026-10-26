import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'app_icon_button.dart';

/// Consistent sheet body: drag handle, title row, scrollable content,
/// optional sticky footer, safe-area bottom, max 90% height.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.child,
    this.title,
    this.onClose,
    this.footer,
    this.showHandle = true,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    this.controller,
  });

  final Widget child;
  final String? title;
  final VoidCallback? onClose;
  final Widget? footer;
  final bool showHandle;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          color: ShodashaTheme.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(ShodashaTheme.radiusSheet),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showHandle)
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      bottom: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: ShodashaTheme.muted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      0,
                      AppSpacing.sm,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              title!,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ),
                        if (onClose != null)
                          AppIconButton(
                            icon: Icons.close,
                            tooltip: 'Close',
                            onPressed: onClose,
                          ),
                      ],
                    ),
                  ),
                Flexible(
                  child: SingleChildScrollView(
                    controller: controller,
                    padding: padding,
                    child: child,
                  ),
                ),
                if (footer != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    decoration: const BoxDecoration(
                      color: ShodashaTheme.surface,
                      border: Border(
                        top: BorderSide(color: ShodashaTheme.border),
                      ),
                    ),
                    child: footer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [AppSheet]-friendly content with the shared 90% / transparent shell.
/// Callers keep control of dismiss/back policy while a mutation is in flight.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = true,
  Color? barrierColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor ?? ShodashaTheme.ink.withValues(alpha: 0.45),
    constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
      ),
      child: builder(sheetContext),
    ),
  );
}
