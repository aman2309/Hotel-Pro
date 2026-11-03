import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/widgets/app_toast.dart';
import 'package:my_first_app/widgets/custom_bottom_sheet.dart';
import 'package:my_first_app/widgets/custom_dialog.dart';

void main() {
  for (final keyboard in [0.0, 240.0]) {
    testWidgets(
      'sheet buttons and overlay feedback respect system bars, keyboard=$keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
        tester.view.padding = FakeViewPadding(
          top: 24,
          bottom: keyboard == 0 ? 48 : 0,
        );
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showCustomBottomSheet<void>(
                    context: context,
                    builder: (context) => CustomDialog(
                      title: const Text('Booking'),
                      content: const SizedBox(height: 800),
                      actions: [
                        TextButton(
                          onPressed: () => showAppToast(
                            context,
                            'Photo upload failed. Retry.',
                          ),
                          child: const Text('Confirm test'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final confirm = find.text('Confirm test');
        await tester.ensureVisible(confirm);
        expect(
          tester.getRect(confirm).bottom,
          lessThanOrEqualTo(640 - (keyboard == 0 ? 48 : keyboard)),
        );
        await tester.tap(confirm);
        await tester.pump();
        expect(find.text('Photo upload failed. Retry.'), findsOneWidget);
        expect(
          tester.getRect(find.text('Photo upload failed. Retry.')).top,
          greaterThanOrEqualTo(24),
        );
        await tester.tap(find.byTooltip('Dismiss message'));
        await tester.pump();
        expect(find.text('Photo upload failed. Retry.'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
