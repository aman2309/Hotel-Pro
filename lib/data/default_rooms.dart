/// Room numbers, types, and rents copied from the original dashboard list.
class DefaultRoomSpec {
  const DefaultRoomSpec(this.roomNumber, this.roomType, this.normalRent);

  final int roomNumber;
  final String roomType;
  final int normalRent;
}

const List<DefaultRoomSpec> kDefaultRoomSpecs = <DefaultRoomSpec>[
  DefaultRoomSpec(101, 'Deluxe', 1500),
  DefaultRoomSpec(102, 'Luxury', 2000),
  DefaultRoomSpec(103, 'Deluxe', 1500),
  DefaultRoomSpec(104, 'Luxury', 2000),
  DefaultRoomSpec(105, 'Deluxe', 1500),
  DefaultRoomSpec(106, 'Luxury', 2000),
  DefaultRoomSpec(107, 'Deluxe', 1500),
  DefaultRoomSpec(108, 'Suite', 2500),
  DefaultRoomSpec(109, 'Deluxe', 1500),
  DefaultRoomSpec(110, 'Luxury', 2000),
  DefaultRoomSpec(111, 'Deluxe', 1500),
  DefaultRoomSpec(112, 'Suite', 2500),
];
