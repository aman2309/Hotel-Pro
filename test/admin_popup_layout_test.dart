import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/admin/admin_dialog.dart';

void main() {
  for (final size in [
    const Size(360, 640),
    const Size(740, 360),
    const Size(1440, 1000),
  ]) {
    testWidgets(
      'admin popup stays centered and its actions are reachable at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showAdminDialog<void>(
                    context: context,
                    builder: (context) => AdminDialog(
                      title: const Text('Admin popup'),
                      content: const SizedBox(
                        height: 600,
                        child: Text('Popup contents'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Done'),
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
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        final bounds = tester.getRect(find.byType(AdminDialog));
        expect(bounds.center.dx, closeTo(size.width / 2, 1));
        expect(bounds.left, greaterThanOrEqualTo(24));
        expect(bounds.bottom, lessThan(size.height));
        await tester.ensureVisible(find.text('Done'));
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
