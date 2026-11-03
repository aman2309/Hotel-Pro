import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/screens/hotel_dashboard_view.dart';

void main() {
  testWidgets(
    'Home shows loading before data and empty state only after an empty result',
    (tester) async {
      Future<void> show({
        required bool loading,
        List<Room> rooms = const [],
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: HotelDashboardView(
              hotelName: 'Test Hotel',
              rooms: rooms,
              roomsLoading: loading,
              onAction: (_) {},
              onOpenRoom: (_) {},
              onRefresh: () async {},
            ),
          ),
        );
        await tester.pump();
      }

      await show(loading: true);
      expect(find.text('Loading your rooms…'), findsOneWidget);
      expect(find.text('Add your first room'), findsNothing);
      expect(find.text('Add room'), findsNothing);
      await show(
        loading: false,
        rooms: [Room(roomNumber: 101, roomType: 'Standard', normalRent: 1000)],
      );
      expect(find.text('Loading your rooms…'), findsNothing);
      expect(find.text('ROOM 101'), findsOneWidget);
      expect(find.text('Add your first room'), findsNothing);
      await show(loading: false);
      expect(find.text('Loading your rooms…'), findsNothing);
      expect(find.text('Add your first room'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
