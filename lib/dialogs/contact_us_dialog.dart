import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/custom_colors.dart';
import '../widgets/app_toast.dart';
import '../widgets/custom_bottom_sheet.dart';
import '../widgets/custom_dialog.dart';

// TODO: replace with the real Hotel Pro support details.
const supportEmail = 'yankees.res@gmail.com';
const supportMobile = '+91 9893281818';

Future<void> showContactUsDialog(BuildContext context) =>
    showCustomBottomSheet<void>(
      context: context,
      builder: (context) => CustomDialog(
        title: const Text('Contact us'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Need help with Hotel Pro? Reach us here. Tap to copy.',
                style: TextStyle(color: CustomColors.muted),
              ),
            ),
            for (final c in const [
              ('Email', supportEmail, Icons.email_outlined),
              ('Mobile number', supportMobile, Icons.phone_outlined),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(c.$3, color: CustomColors.primary),
                title: Text(c.$1),
                subtitle: SelectableText(c.$2),
                trailing: const Icon(Icons.copy_rounded, size: 18),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: c.$2));
                  if (context.mounted) {
                    showAppToast(context, '${c.$1} copied', error: false);
                  }
                },
              ),
          ],
        ),
      ),
    );
