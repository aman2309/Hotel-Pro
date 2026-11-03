import 'package:flutter/material.dart';
import '../theme/custom_colors.dart';
import '../widgets/custom_dialog.dart';

/// Admin actions use centered web dialogs; the hotel app keeps its sheets.
Future<T?> showAdminDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  useSafeArea: true,
  builder: (context) {
    final media = MediaQuery.of(context);
    final availableHeight =
        (media.size.height -
                media.viewInsets.bottom -
                media.padding.vertical -
                48)
            .clamp(80.0, media.size.height);
    return Dialog(
      alignment: Alignment.center,
      backgroundColor: CustomColors.surface,
      surfaceTintColor: CustomColors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 680, maxHeight: availableHeight),
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: SizedBox(width: double.infinity, child: builder(context)),
        ),
      ),
    );
  },
);

class AdminDialog extends CustomDialog {
  const AdminDialog({
    super.key,
    required super.title,
    super.content,
    super.actions,
    super.canClose,
    super.notice,
  }) : super(closeTooltip: 'Close dialog');
}
