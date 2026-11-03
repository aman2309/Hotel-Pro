import 'package:flutter/material.dart';
import '../models/room.dart';
import '../theme/custom_colors.dart';
import '../widgets/hotel_ui.dart';
import '../widgets/hotel_room_card.dart';
import '../widgets/custom_bottom_sheet.dart';
import '../widgets/hotel_settings_form.dart';
import '../widgets/hotel_cloud_status_chip.dart';

class HotelDashboardView extends StatefulWidget {
  const HotelDashboardView({
    super.key,
    required this.hotelName,
    required this.rooms,
    required this.onAction,
    required this.onOpenRoom,
    required this.onRefresh,
    this.membershipBanner,
    this.roomsLoading = false,
    this.onEditRoom,
    this.onDeleteRoom,
    this.onSettingsSaved,
  });
  final bool roomsLoading;
  final String hotelName;
  final List<Room> rooms;
  final ValueChanged<String> onAction;
  final ValueChanged<Room> onOpenRoom;
  final Future<void> Function() onRefresh;
  final Widget? membershipBanner;
  final Future<void> Function(Room)? onEditRoom, onDeleteRoom;
  final VoidCallback? onSettingsSaved;
  @override
  State<HotelDashboardView> createState() => _HotelDashboardViewState();
}

class _HotelDashboardViewState extends State<HotelDashboardView> {
  int _section = 0;
  String? _status;
  int? _busyRoom;
  static const _states = [
    ('EMPTY', 'Available', CustomColors.available, CustomColors.availableTint),
    ('BOOKED', 'Booked', CustomColors.booked, CustomColors.bookedTint),
    ('CLEANING', 'Cleaning', CustomColors.cleaning, CustomColors.cleaningTint),
    ('CLOSED', 'Closed', CustomColors.closed, CustomColors.closedTint),
  ];
  static const _actions = [
    ('add', 'Add room', Icons.add_home_outlined),
    ('edit', 'Edit room', Icons.edit_outlined),
    ('customers', 'Guests', Icons.people_outline_rounded),
    ('reports', 'Reports', Icons.insights_rounded),
    ('expenses', 'Expenses', Icons.account_balance_wallet_outlined),
    ('settings', 'Hotel settings', Icons.tune_rounded),
    ('delete', 'Delete room', Icons.delete_outline_rounded),
    ('logout', 'Sign out', Icons.logout_rounded),
  ];
  Future<void> _options() async {
    final action = await showCustomBottomSheet<String>(
      context: context,
      builder: (context) => CustomDialog(
        title: const Text('Hotel options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in _actions)
              ListTile(
                leading: Icon(
                  a.$3,
                  color: a.$1 == 'logout'
                      ? CustomColors.error
                      : CustomColors.primary,
                ),
                title: Text(a.$2),
                onTap: () => Navigator.pop(context, a.$1),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    _dispatch(action);
  }

  void _selectSection(int index) {
    FocusScope.of(context).unfocus();
    setState(() => _section = index);
  }

  void _dispatch(String action) {
    if (action == 'settings') {
      _selectSection(3);
    } else if (action == 'edit' || action == 'delete') {
      _selectSection(1);
    } else {
      widget.onAction(action);
    }
  }

  Future<void> _roomAction(Room room, bool delete) async {
    final action = delete ? widget.onDeleteRoom : widget.onEditRoom;
    if (_busyRoom != null || action == null) return;
    setState(() => _busyRoom = room.roomNumber);
    try {
      await action(room);
    } finally {
      if (mounted) setState(() => _busyRoom = null);
    }
  }

  List<Widget> _editRooms() => [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                const title = Text(
                  'Edit rooms',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                );
                final add = CustomButton.outlineIcon(
                  onPressed: _busyRoom == null
                      ? () => widget.onAction('add')
                      : null,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add room'),
                );
                if (constraints.maxWidth < 420 &&
                    MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 10), add],
                  );
                }
                return Row(
                  children: [
                    const Expanded(child: title),
                    add,
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.rooms.length} rooms · Pull down to refresh',
              style: const TextStyle(color: CustomColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              'Rooms with an active or upcoming booking stay protected.',
              style: TextStyle(color: CustomColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
    if (widget.rooms.isEmpty)
      const SliverFillRemaining(
        hasScrollBody: false,
        child: CustomEmptyState(
          title: 'No rooms yet',
          message: 'Add your first room to manage it here.',
          icon: Icons.meeting_room_outlined,
        ),
      )
    else
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverList.builder(
          itemCount: widget.rooms.length,
          itemBuilder: (context, index) {
            final room = widget.rooms[index];
            final available = room.status != 'BOOKED' && !room.futureBooking;
            final (label, color) = switch (room.status) {
              'EMPTY' => (
                room.futureBooking ? 'Upcoming booking' : 'Available',
                CustomColors.available,
              ),
              'BOOKED' => ('Booked', CustomColors.booked),
              'CLEANING' => ('Cleaning', CustomColors.cleaning),
              _ => ('Closed', CustomColors.closed),
            };
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CustomSurface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.cardTitle,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_busyRoom == room.roomNumber)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          CustomStatusBadge(label: label, color: color),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${room.roomType} · ${room.normalRent > 0 ? '₹${room.normalRent} / day' : 'Rent not set'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: CustomColors.muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stack =
                            constraints.maxWidth < 300 &&
                            MediaQuery.textScalerOf(context).scale(1) > 1.3;
                        final width = stack
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 10) / 2;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: width,
                              child: CustomButton.outlineIcon(
                                key: ValueKey('edit-room-${room.roomNumber}'),
                                onPressed:
                                    available &&
                                        _busyRoom == null &&
                                        widget.onEditRoom != null
                                    ? () => _roomAction(room, false)
                                    : null,
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: const Text('Edit'),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: CustomButton.outlineIcon(
                                key: ValueKey('delete-room-${room.roomNumber}'),
                                onPressed:
                                    available &&
                                        _busyRoom == null &&
                                        widget.onDeleteRoom != null
                                    ? () => _roomAction(room, true)
                                    : null,
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                                label: const Text('Delete'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
  ];

  Widget _statusTiles() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Row(
      spacing: 6,
      children: [
        for (final state in _states)
          Expanded(
            child: Semantics(
              button: true,
              selected: _status == state.$1,
              label:
                  '${state.$2}, ${widget.rooms.where((r) => r.status == state.$1).length} rooms',
              child: Material(
                color: state.$4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _status == state.$1
                        ? state.$3
                        : CustomColors.transparent,
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(
                    () => _status = _status == state.$1 ? null : state.$1,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 9,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.rooms.where((r) => r.status == state.$1).length}',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                            color: state.$3,
                          ),
                        ),
                        const SizedBox(height: 5),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            state.$2,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: state.$3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  List<Widget> _home(BuildContext context) {
    final visible = widget.rooms
        .where((r) => _status == null || r.status == _status)
        .toList();
    return [
      SliverToBoxAdapter(child: _statusTiles()),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 3, 8, 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _status == null
                      ? 'All rooms · ${widget.rooms.length}'
                      : '${visible.length} rooms shown',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_status != null)
                CustomButton.text(
                  onPressed: () => setState(() => _status = null),
                  child: const Text('Show all'),
                ),
            ],
          ),
        ),
      ),
      if (visible.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: CustomEmptyState(
            title: widget.rooms.isEmpty
                ? 'Add your first room'
                : 'No rooms with this status',
            message: widget.rooms.isEmpty
                ? 'Add a room number, type and rent to get started.'
                : 'Tap the selected status again or show all rooms.',
            icon: Icons.meeting_room_outlined,
            action: CustomButton.icon(
              onPressed: () {
                if (widget.rooms.isEmpty) {
                  widget.onAction('add');
                } else {
                  setState(() => _status = null);
                }
              },
              icon: Icon(
                widget.rooms.isEmpty
                    ? Icons.add_rounded
                    : Icons.grid_view_rounded,
              ),
              label: Text(widget.rooms.isEmpty ? 'Add room' : 'Show all rooms'),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) => SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (constraints.crossAxisExtent / 106)
                    .floor()
                    .clamp(2, 8),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                mainAxisExtent:
                    128 + (MediaQuery.textScalerOf(context).scale(20) - 20) * 3,
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final room = visible[i];
                return HotelRoomCard(
                  room: room,
                  onTap: () => widget.onOpenRoom(room),
                  timeLabel: room.bookingTime?.toString() ?? '',
                  futureLabel:
                      room.futureBooking && room.futureBookingDate != null
                      ? room.futureBookingDate.toString()
                      : null,
                );
              }, childCount: visible.length),
            ),
          ),
        ),
    ];
  }

  List<Widget> _settings() => [
    const SliverPadding(
      padding: EdgeInsets.all(18),
      sliver: SliverToBoxAdapter(
        child: Text(
          'Hotel settings',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
      sliver: SliverToBoxAdapter(
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: CustomSurface(
              child: HotelSettingsForm(onSaved: widget.onSettingsSaved),
            ),
          ),
        ),
      ),
    ),
  ];

  List<Widget> _more() => [
    SliverToBoxAdapter(
      child: widget.membershipBanner ?? const SizedBox.shrink(),
    ),
    const SliverPadding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Hotel tools',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            HotelCloudStatusChip(),
          ],
        ),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      sliver: SliverList.list(
        children: [
          for (final a in _actions.where(
            (a) => !['add', 'edit', 'delete', 'settings'].contains(a.$1),
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CustomSurface(
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 5,
                  ),
                  leading: Icon(
                    a.$3,
                    color: a.$1 == 'logout'
                        ? CustomColors.error
                        : CustomColors.primary,
                  ),
                  title: Text(a.$2, style: const TextStyle(fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                  onTap: () => widget.onAction(a.$1),
                ),
              ),
            ),
        ],
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: CustomColors.background,
      foregroundColor: CustomColors.text,
      leading: const Icon(Icons.apartment_rounded, color: CustomColors.button),
      titleSpacing: 0,
      title: Text(
        widget.hotelName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      actions: [
        IconButton(
          tooltip: 'Hotel options',
          onPressed: _options,
          icon: const Icon(Icons.more_vert_rounded),
        ),
      ],
    ),
    body: IndexedStack(
      index: _section,
      children: [
        for (final section in [0, 1, 2, 3])
          RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: CustomScrollView(
              key: PageStorageKey('hotel-section-$section'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: widget.roomsLoading && section < 2
                  ? const [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Loading your rooms…'),
                            ],
                          ),
                        ),
                      ),
                    ]
                  : section == 0
                  ? _home(context)
                  : section == 1
                  ? _editRooms()
                  : section == 2
                  ? _more()
                  : _settings(),
            ),
          ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CustomColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: CustomColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: NavigationBar(
              backgroundColor: CustomColors.surface,
              surfaceTintColor: CustomColors.transparent,
              indicatorColor: CustomColors.neutralTint,
              height: 68,
              labelPadding: const EdgeInsets.symmetric(horizontal: 2),
              labelTextStyle: const WidgetStatePropertyAll(
                TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              selectedIndex: _section,
              onDestinationSelected: _selectSection,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.edit_note_outlined),
                  selectedIcon: Icon(Icons.edit_note_rounded),
                  label: 'Edit rooms',
                ),
                NavigationDestination(
                  icon: Icon(Icons.widgets_outlined),
                  selectedIcon: Icon(Icons.widgets_rounded),
                  label: 'More',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
