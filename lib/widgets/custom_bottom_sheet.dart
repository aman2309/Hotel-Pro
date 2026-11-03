import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode;
import '../theme/custom_colors.dart';
import 'custom_button.dart';
import 'custom_dialog.dart';

/// One route for forms, confirmations, previews and nested pickers.
Future<T?> showCustomBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  Color? backgroundColor,
  ShapeBorder? shape,
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: useRootNavigator,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: barrierDismissible,
  enableDrag: barrierDismissible,
  showDragHandle: true,
  backgroundColor: backgroundColor ?? CustomColors.surface,
  shape:
      shape ??
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
  clipBehavior: Clip.antiAlias,
  constraints: const BoxConstraints(maxWidth: 840),
  builder: (context) {
    final media = MediaQuery.of(context);
    final height =
        (media.size.height - media.viewInsets.bottom - media.padding.top - 64)
            .clamp(80.0, media.size.height);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: height - media.padding.bottom,
            ),
            child: SizedBox(width: double.infinity, child: builder(context)),
          ),
        ),
      ),
    );
  },
);

/// A bounded panel for full-height photo/PDF content.
class CustomSheetPanel extends StatelessWidget {
  const CustomSheetPanel({super.key, required this.child, this.insetPadding});
  final Widget child;
  final EdgeInsets? insetPadding;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: double.infinity, child: child);
}

Future<DateTime?> showCustomDateSheet({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  FocusScope.of(context).unfocus();
  var selected = initialDate;
  return showCustomBottomSheet<DateTime>(
    context: context,
    builder: (context) => CustomDialog(
      title: const Text('Choose date'),
      content: CalendarDatePicker(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        onDateChanged: (value) => selected = value,
      ),
      actions: [
        CustomButton.text(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        CustomButton(
          onPressed: () => Navigator.pop(context, selected),
          child: const Text('Use date'),
        ),
      ],
    ),
  );
}

Future<TimeOfDay?> showCustomTimeSheet({
  required BuildContext context,
  required TimeOfDay initialTime,
  String title = 'Choose time',
}) {
  var selected = initialTime;
  FocusScope.of(context).unfocus();
  return showCustomBottomSheet<TimeOfDay>(
    context: context,
    builder: (context) => CustomDialog(
      title: Text(title),
      content: SizedBox(
        height: 216,
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          initialDateTime: DateTime(
            2000,
            1,
            1,
            initialTime.hour,
            initialTime.minute,
          ),
          use24hFormat: false,
          onDateTimeChanged: (date) => selected = TimeOfDay.fromDateTime(date),
        ),
      ),
      actions: [
        CustomButton.text(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        CustomButton(
          onPressed: () => Navigator.pop(context, selected),
          child: const Text('Use time'),
        ),
      ],
    ),
  );
}
