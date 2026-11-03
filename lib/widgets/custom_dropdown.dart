import 'package:flutter/material.dart';
import '../theme/custom_colors.dart';
import 'custom_bottom_sheet.dart';
import 'custom_dialog.dart';

/// Form selection uses the same sheet as every other app overlay.
class CustomDropdown<T> extends FormField<T> {
  CustomDropdown({
    super.key,
    super.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.focusNode,
    this.autofocus = false,
    this.isExpanded = true,
    super.validator,
  }) : super(
         enabled: onChanged != null,
         builder: (state) {
           final field = state.widget as CustomDropdown<T>;
           DropdownMenuItem<T>? selected;
           for (final item in field.items ?? <DropdownMenuItem<T>>[]) {
             if (item.value == state.value) {
               selected = item;
               break;
             }
           }
           Future<void> select() async {
             FocusScope.of(state.context).unfocus();
             final result = await showCustomBottomSheet<DropdownMenuItem<T>>(
               context: state.context,
               builder: (context) => CustomDialog(
                 title: Text(field.decoration.labelText ?? 'Choose an option'),
                 content: Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     for (final item in field.items ?? <DropdownMenuItem<T>>[])
                       ListTile(
                         enabled: item.enabled,
                         title: item.child,
                         trailing: Icon(
                           item.value == state.value
                               ? Icons.radio_button_checked
                               : Icons.radio_button_off,
                           color: item.value == state.value
                               ? CustomColors.primary
                               : CustomColors.muted,
                         ),
                         onTap: item.enabled
                             ? () => Navigator.pop(context, item)
                             : null,
                       ),
                   ],
                 ),
               ),
             );
             if (!state.mounted || result == null) return;
             state.didChange(result.value);
             result.onTap?.call();
             field.onChanged?.call(result.value);
           }

           final border = OutlineInputBorder(
             borderRadius: BorderRadius.circular(16),
             borderSide: const BorderSide(color: CustomColors.border),
           );
           return Padding(
             padding: const EdgeInsets.only(bottom: 14),
             child: Semantics(
               button: true,
               enabled: field.onChanged != null,
               child: InkWell(
                 focusNode: field.focusNode,
                 autofocus: field.autofocus,
                 borderRadius: BorderRadius.circular(16),
                 onTap: field.onChanged == null ? null : select,
                 child: InputDecorator(
                   isEmpty: selected == null,
                   decoration: field.decoration.copyWith(
                     enabled: field.onChanged != null,
                     errorText: state.errorText,
                     filled: true,
                     fillColor: CustomColors.fieldBackground,
                     labelStyle: const TextStyle(
                       color: CustomColors.muted,
                       fontSize: 13,
                     ),
                     border: border,
                     enabledBorder: border,
                     focusedBorder: OutlineInputBorder(
                       borderRadius: BorderRadius.circular(16),
                       borderSide: const BorderSide(
                         color: CustomColors.primary,
                         width: 2,
                       ),
                     ),
                   ),
                   child: Row(
                     children: [
                       Expanded(
                         child: DefaultTextStyle(
                           style: const TextStyle(
                             fontFamily: 'Poppins',
                             fontSize: 13,
                             color: CustomColors.text,
                           ),
                           child: selected?.child ?? const SizedBox(height: 20),
                         ),
                       ),
                       const Icon(
                         Icons.expand_more_rounded,
                         color: CustomColors.muted,
                       ),
                     ],
                   ),
                 ),
               ),
             ),
           );
         },
       );
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final FocusNode? focusNode;
  final bool autofocus, isExpanded;
  @override
  FormFieldState<T> createState() => _SheetDropdownState<T>();
}

class _SheetDropdownState<T> extends FormFieldState<T> {
  @override
  void didUpdateWidget(covariant CustomDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }
}
