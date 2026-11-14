import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_saver/file_saver.dart';
import '../theme/custom_colors.dart';
import '../widgets/hotel_ui.dart';
import 'admin_dialog.dart';
import '../widgets/app_toast.dart';
import 'admin_api.dart';
import 'admin_widgets.dart';
import 'admin_key_dialog.dart';

class AdminConsole extends StatefulWidget {
  const AdminConsole({
    super.key,
    required this.onSignOut,
    required this.email,
    this.api,
  });
  final Future<void> Function() onSignOut;
  final String email;
  final AdminApi? api;
  @override
  State<AdminConsole> createState() => _AdminConsoleState();
}

class _AdminConsoleState extends State<AdminConsole> {
  late final AdminApi _api = widget.api ?? AdminApi();
  final List<Map<String, dynamic>> _hotels = [],
      _keys = [],
      _audit = [],
      _records = [];
  final _search = TextEditingController();
  int _section = 0, _days = 30, _detailTicket = 0;
  final Set<String> _deletingIds = {};
  String _hotelFilter = 'All', _collection = 'rooms';
  String? _hotelCursor, _keyCursor, _auditCursor, _recordCursor, _error;
  Map<String, dynamic>? _selected, _detail, _revenue;
  bool _busy = true, _detailBusy = false, _recordBusy = false;
  DateTime? _loadedAt;
  static const _nav = [
    ('Overview', Icons.space_dashboard_outlined),
    ('Hotels', Icons.apartment_rounded),
    ('License keys', Icons.key_rounded),
    ('Activity', Icons.history_rounded),
  ];
  static const _collections = [
    'rooms',
    'bookings',
    'futureBookings',
    'guests',
    'bills',
    'payments',
    'expenses',
    'closedRooms',
    'extraCharges',
    'settings',
  ];
  static const _labels = {
    'rooms': 'Rooms',
    'bookings': 'Bookings',
    'futureBookings': 'Future bookings',
    'guests': 'Guests',
    'bills': 'Bills',
    'payments': 'Payments',
    'expenses': 'Expenses',
    'closedRooms': 'Closed rooms',
    'extraCharges': 'Extra charges',
    'settings': 'Hotel settings',
  };
  @override
  void initState() {
    super.initState();
    _loadHotels();
    _loadRevenue();
  }

  Future<void> _loadRevenue() async {
    try {
      final r = await _api.call('adminLicenseRevenue');
      if (mounted) setState(() => _revenue = r);
    } catch (e) {
      _fail(e);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() => _error = adminFailure(error));
    showAppToast(context, _error!);
  }

  Future<void> _loadHotels({bool more = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.call('adminListHotelsV2', {
        'limit': 30,
        if (more && _hotelCursor != null) 'after': _hotelCursor,
      });
      if (!mounted) return;
      setState(() {
        if (!more) _hotels.clear();
        _hotels.addAll(adminItems(r));
        _hotelCursor = r['nextCursor'] as String?;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadKeys({bool more = false}) async {
    setState(() => _busy = true);
    try {
      final r = await _api.call('adminListLicenseKeys', {
        'limit': 50,
        if (more && _keyCursor != null) 'after': _keyCursor,
      });
      if (!mounted) return;
      setState(() {
        if (!more) _keys.clear();
        _keys.addAll(adminItems(r));
        _keyCursor = r['nextCursor'] as String?;
        _error = null;
      });
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadAudit({bool more = false}) async {
    setState(() => _busy = true);
    try {
      final r = await _api.call('adminAuditLog', {
        if (more && _auditCursor != null) 'after': _auditCursor,
      });
      if (!mounted) return;
      setState(() {
        if (!more) _audit.clear();
        _audit.addAll(adminItems(r));
        _auditCursor = r['nextCursor'] as String?;
        _error = null;
      });
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _go(int section) {
    if (_busy || _detailBusy) return;
    setState(() {
      _section = section;
      _selected = null;
      _detail = null;
      _error = null;
    });
    if (section == 2) _loadKeys();
    if (section == 3) _loadAudit();
  }

  Future<void> _refresh() async {
    if (_selected != null) {
      await _openHotel(_selected!);
      return;
    }
    if (_section == 2) {
      await _loadKeys();
      return;
    }
    if (_section == 3) {
      await _loadAudit();
      return;
    }
    await Future.wait([_loadHotels(), _loadRevenue()]);
  }

  Future<void> _openHotel(Map<String, dynamic> hotel) async {
    final ticket = ++_detailTicket;
    setState(() {
      _selected = hotel;
      _detailBusy = true;
      _detail = null;
      _error = null;
      _records.clear();
    });
    try {
      final r = await _api.call('adminHotelDetails', {
        'hotelId': hotel['hotelId'],
        if (_days > 0)
          'from': DateTime.now()
              .subtract(Duration(days: _days))
              .toUtc()
              .toIso8601String(),
      });
      if (!mounted || ticket != _detailTicket) return;
      setState(() => _detail = r);
      await _loadRecords();
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted && ticket == _detailTicket) {
        setState(() => _detailBusy = false);
      }
    }
  }

  Future<void> _loadRecords({bool more = false}) async {
    if (_selected == null) return;
    final hotelId = _selected!['hotelId'], collection = _collection;
    setState(() => _recordBusy = true);
    try {
      final r = await _api.call('adminHotelRecords', {
        'hotelId': hotelId,
        'collection': collection,
        'limit': 50,
        if (more && _recordCursor != null) 'after': _recordCursor,
      });
      if (!mounted ||
          _selected?['hotelId'] != hotelId ||
          _collection != collection) {
        return;
      }
      setState(() {
        if (!more) _records.clear();
        _records.addAll(adminItems(r));
        _recordCursor = r['nextCursor'] as String?;
      });
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _recordBusy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showAdminDialog<bool>(
        context: context,
        builder: (context) => AdminDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep unchanged'),
            ),
            CustomButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _setEnabled() async {
    final hotel = _detail ?? _selected;
    if (hotel == null) return;
    final enabled = hotel['enabled'] != false;
    if (!await _confirm(
      enabled ? 'Suspend hotel?' : 'Resume hotel?',
      enabled
          ? 'The hotel keeps its records but cannot make changes until resumed.'
          : 'Restore access according to this hotel’s membership validity.',
      enabled ? 'Suspend hotel' : 'Resume hotel',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _detailBusy = true);
    try {
      await _api.call('adminSetHotelEnabled', {
        'hotelId': hotel['hotelId'],
        'enabled': !enabled,
      });
      await _openHotel(hotel);
      await _loadHotels();
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _detailBusy = false);
    }
  }

  /// Admin must type DELETE: removal is permanent, not a draft.
  Future<bool> _confirmDelete(String name) async =>
      await showAdminDialog<bool>(
        context: context,
        builder: (context) => _DeleteHotelDialog(name: name),
      ) ==
      true;

  Future<void> _deleteHotel([Map<String, dynamic>? target]) async {
    final hotel = target ?? _detail ?? _selected;
    if (hotel == null || _detailBusy) return;
    final id = '${hotel['hotelId']}';
    if (_deletingIds.contains(id)) return;
    if (!await _confirmDelete('${hotel['hotelName']}') || !mounted) return;
    setState(() {
      _detailBusy = true;
      _deletingIds.add(id);
    });
    try {
      await _api.call('adminDeleteHotel', {
        'hotelId': id,
        'confirmHotelId': id,
      });
      if (!mounted) return;
      setState(() {
        if (_selected?['hotelId'] == id) {
          _selected = null;
          _detail = null;
          _section = 1;
        }
        _hotels.removeWhere((hotel) => hotel['hotelId'] == id);
      });
      showAppToast(context, 'Hotel deleted permanently.', error: false);
      await _loadHotels();
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) {
        setState(() {
          _detailBusy = false;
          _deletingIds.remove(id);
        });
      }
    }
  }

  Future<void> _issueKey({String? hotelId}) async {
    final result = await showAdminDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          AdminKeyDialog(api: _api, hotels: _hotels, hotelId: hotelId),
    );
    if (result == null || !mounted) return;
    unawaited(_loadRevenue());
    await _showGeneratedKey(result);
    if (_section == 2) await _loadKeys();
  }

  Future<void> _showGeneratedKey(Map<String, dynamic> result) async {
    final key = '${result['key']}';
    final plan =
        '${result['planLabel']} plan · ${adminMoney(result['amount'])} paid';
    await showAdminDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AdminDialog(
        title: const Text('Your license key is ready'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SelectableText(
              key,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Copy or download this key now. For security, the full key is not shown again in the key list. Share it with the hotel owner to enter in the app’s membership screen.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
          CustomButton.outlineIcon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: key));
              if (context.mounted) {
                showAppToast(context, 'Key copied.', error: false);
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy key'),
          ),
          CustomButton.icon(
            onPressed: () => FileSaver.instance.saveFile(
              name: 'hotel-pro-license',
              bytes: Uint8List.fromList(
                utf8.encode('Hotel Pro license\nPlan: $plan\n$key\n'),
              ),
              fileExtension: 'txt',
              mimeType: MimeType.text,
            ),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(Map<String, dynamic> key) async {
    if (!await _confirm(
      'Revoke unused key?',
      'This key will no longer activate a hotel.',
      'Revoke key',
    )) {
      return;
    }
    try {
      await _api.call('adminRevokeLicenseKey', {'keyId': key['keyId']});
      await _loadKeys();
    } catch (e) {
      _fail(e);
    }
  }

  Widget _hotelList(
    List<Map<String, dynamic>> hotels, {
    bool allowDelete = false,
  }) => Column(
    children: [
      for (final h in hotels)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AdminCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CustomColors.neutralTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.apartment_rounded),
              ),
              title: Text(
                '${h['hotelName']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${h['phoneNumber'] ?? ''}  ·  ${adminMap(h['rooms'])['total'] ?? 0} rooms\n${adminPlanLine(adminMap(h['license'])).isEmpty ? h['email'] ?? '' : adminPlanLine(adminMap(h['license']))}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: CustomColors.muted,
                  ),
                ),
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AdminStatus('${h['status']}'),
                      const SizedBox(height: 4),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: CustomColors.muted,
                      ),
                    ],
                  ),
                  if (allowDelete) ...[
                    const SizedBox(width: 8),
                    _deletingIds.contains('${h['hotelId']}')
                        ? const SizedBox(
                            width: 40,
                            height: 40,
                            child: Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Delete hotel permanently',
                            onPressed: _detailBusy
                                ? null
                                : () => _deleteHotel(h),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: CustomColors.error,
                            ),
                          ),
                  ],
                ],
              ),
              onTap: () => _openHotel(h),
            ),
          ),
        ),
      if (hotels.isEmpty)
        const AdminCard(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No hotels found.'),
            ),
          ),
        ),
    ],
  );
  Widget _revenueCard(Map<String, dynamic> revenue) {
    final plans = adminItems({'items': revenue['plans']});
    final months = adminItems({'items': revenue['months']});
    final top = months.fold<num>(1, (m, e) => max(m, adminNumber(e['amount'])));
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    String monthName(String key) {
      final m = int.tryParse(key.split('-').last) ?? 1;
      return names[(m - 1).clamp(0, 11)];
    }

    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionTitle(
            'Membership revenue',
            subtitle:
                'From paid license keys · ${adminMoney(revenue['total'])} in total',
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final p in plans)
                Container(
                  width: 168,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: CustomColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CustomColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['label']} · ${adminMoney(p['price'])}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: CustomColors.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        adminMoney(p['amount']),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${p['count']} sold',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Last 6 months',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          for (final m in months)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      monthName('${m['month']}'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (adminNumber(m['amount']) / top).toDouble(),
                      minHeight: 9,
                      color: CustomColors.available,
                      backgroundColor: CustomColors.neutralTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 84,
                    child: Text(
                      adminMoney(m['amount']),
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _overview() {
    num sum(String field) => _hotels.fold<num>(
      0,
      (n, h) => n + adminNumber(adminMap(h['rooms'])[field]),
    );
    final total = sum('total'), booked = sum('booked');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSectionTitle(
          'A clear view of your hotels',
          subtitle: _hotelCursor == null
              ? 'All hotels connected to this Firebase project'
              : 'Metrics for ${_hotels.length} loaded hotels · Load more for complete totals',
          action: CustomButton.icon(
            onPressed: _busy ? null : () => _issueKey(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Generate key'),
          ),
        ),
        AdminMetricGrid(
          children: [
            AdminMetric(
              title: 'Hotels',
              value: '${_hotels.length}',
              icon: Icons.apartment_rounded,
              note:
                  '${_hotels.where((h) => h['enabled'] != false).length} enabled',
            ),
            AdminMetric(
              title: 'Active memberships',
              value: '${_hotels.where((h) => h['status'] == 'Active').length}',
              icon: Icons.verified_outlined,
              note:
                  '${_hotels.where((h) => h['status'] == 'Trial').length} hotels on trial',
            ),
            AdminMetric(
              title: 'Total revenue',
              value: _revenue == null ? '—' : adminMoney(_revenue!['total']),
              icon: Icons.currency_rupee_rounded,
              note: _revenue == null
                  ? 'Loading payments…'
                  : '${adminMoney(_revenue!['thisMonth'])} this month · ${_revenue!['count']} paid keys',
            ),
            AdminMetric(
              title: 'Rooms',
              value: '$total',
              icon: Icons.bed_outlined,
              note: '${sum('available')} currently available',
            ),
            AdminMetric(
              title: 'Current occupancy',
              value: total == 0
                  ? '0%'
                  : '${(100 * booked / total).toStringAsFixed(1)}%',
              icon: Icons.donut_large_rounded,
              note: '$booked of $total rooms occupied',
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_revenue != null) ...[
          _revenueCard(_revenue!),
          const SizedBox(height: 24),
        ],
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AdminSectionTitle(
                'Room availability',
                subtitle: 'Current state across loaded hotels',
              ),
              for (final state in [
                ('available', CustomColors.available),
                ('booked', CustomColors.booked),
                ('cleaning', CustomColors.cleaning),
                ('closed', CustomColors.closed),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          state.$1[0].toUpperCase() + state.$1.substring(1),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: total == 0
                              ? 0
                              : (sum(state.$1) / total).toDouble(),
                          minHeight: 9,
                          color: state.$2,
                          backgroundColor: CustomColors.neutralTint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 38,
                        child: Text(
                          '${sum(state.$1)}',
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        AdminSectionTitle(
          'Your hotels',
          subtitle: 'Open a hotel to view its data and analytics',
          action: TextButton(
            onPressed: () => _go(1),
            child: const Text('View all hotels →'),
          ),
        ),
        _hotelList(_hotels.take(5).toList()),
        if (_hotelCursor != null)
          TextButton(
            onPressed: _busy ? null : () => _loadHotels(more: true),
            child: const Text('Load more hotels'),
          ),
      ],
    );
  }

  Widget _hotelsPage() {
    final search = _search.text.toLowerCase().trim();
    final hotels = _hotels
        .where(
          (h) =>
              (_hotelFilter == 'All' || h['status'] == _hotelFilter) &&
              [
                'hotelName',
                'email',
                'phoneNumber',
                'hotelId',
                'ownerName',
              ].any((k) => '${h[k] ?? ''}'.toLowerCase().contains(search)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSectionTitle(
          'Hotels',
          subtitle: 'Accounts, membership and live hotel operations',
        ),
        CustomTextField(
          controller: _search,
          label: 'Search hotels, owner email or mobile',
          icon: Icons.search_rounded,
          onChanged: (_) => setState(() {}),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in [
              'All',
              'Trial',
              'Active',
              'Expired',
              'Suspended',
            ])
              ChoiceChip(
                label: Text(status),
                selected: _hotelFilter == status,
                onSelected: (_) => setState(() => _hotelFilter = status),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _hotelList(hotels, allowDelete: true),
        if (_hotelCursor != null)
          TextButton(
            onPressed: _busy ? null : () => _loadHotels(more: true),
            child: const Text('Load more hotels'),
          ),
        if (_hotelCursor != null)
          const Text(
            'Search filters the loaded hotels. Load more to search further.',
            style: TextStyle(color: CustomColors.muted, fontSize: 12),
          ),
      ],
    );
  }

  Widget _keysPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AdminSectionTitle(
        'License keys',
        subtitle: 'One-time activation · Month or year validity',
        action: CustomButton.icon(
          onPressed: _busy ? null : () => _issueKey(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Generate key'),
        ),
      ),
      if (_keys.isEmpty && !_busy)
        const AdminCard(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'No keys issued yet. Generate a key to activate a hotel.',
            ),
          ),
        ),
      for (final key in _keys)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AdminCard(
            child: Wrap(
              spacing: 24,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HP-••••-${key['hint']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${key['planLabel'] ?? '${key['durationMonths']} months'}${key['paymentReceived'] == true ? ' · ${adminMoney(key['amount'])} paid' : ''} · Issued ${adminDate(key['createdAt'])}',
                      style: const TextStyle(
                        color: CustomColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _hotelName(key['hotelId']),
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (key['redeemedAt'] != null)
                      Text(
                        'Redeemed ${adminDate(key['redeemedAt'])} · Valid until ${adminDate(key['expiresAt'])}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: CustomColors.muted,
                        ),
                      ),
                  ],
                ),
                AdminStatus('${key['status']}'),
                if (key['status'] == 'issued')
                  TextButton.icon(
                    onPressed: _busy ? null : () => _revoke(key),
                    icon: const Icon(Icons.block_rounded, size: 17),
                    label: const Text('Revoke'),
                  ),
              ],
            ),
          ),
        ),
      if (_keyCursor != null)
        TextButton(
          onPressed: _busy ? null : () => _loadKeys(more: true),
          child: const Text('Load more keys'),
        ),
    ],
  );
  String _hotelName(dynamic id) {
    if (id == null) return 'Unassigned · First hotel to redeem';
    for (final h in _hotels) {
      if (h['hotelId'] == id) return '${h['hotelName']}';
    }
    return '$id';
  }

  Widget _auditPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AdminSectionTitle(
        'Activity',
        subtitle: 'Server-recorded key and hotel access changes',
      ),
      if (_audit.isEmpty && !_busy)
        const AdminCard(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text('No activity yet.'),
          ),
        ),
      for (final a in _audit)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AdminCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.history_rounded, color: CustomColors.muted),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${a['action']}'.replaceAll('-', ' '),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${_hotelName(a['hotelId'])} · ${adminDate(a['createdAt'])}',
                        style: const TextStyle(
                          color: CustomColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      SelectableText(
                        'Actor: ${a['actorUid']}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: CustomColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      if (_auditCursor != null)
        TextButton(
          onPressed: _busy ? null : () => _loadAudit(more: true),
          child: const Text('Load more activity'),
        ),
    ],
  );
  Widget _hotelDetails() {
    final d = _detail;
    if (d == null) {
      return _detailBusy
          ? const Padding(
              padding: EdgeInsets.all(100),
              child: Center(child: CircularProgressIndicator()),
            )
          : const Text('Could not load this hotel. Use refresh to retry.');
    }
    final stats = adminMap(d['analytics']), rooms = adminMap(d['rooms']);
    final series = (stats['series'] as List? ?? []).map(adminMap).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: () {
            ++_detailTicket;
            setState(() {
              _selected = null;
              _detail = null;
            });
          },
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to hotels'),
        ),
        const SizedBox(height: 12),
        AdminSectionTitle(
          '${d['hotelName']}',
          subtitle: '${d['email']} · ${d['phoneNumber']}',
          action: AdminStatus('${d['status']}'),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            CustomButton.icon(
              onPressed: _detailBusy
                  ? null
                  : () => _issueKey(hotelId: '${d['hotelId']}'),
              icon: const Icon(Icons.key_rounded),
              label: const Text('Generate hotel key'),
            ),
            CustomButton.outlineIcon(
              onPressed: _detailBusy || d['deleting'] == true
                  ? null
                  : _setEnabled,
              icon: Icon(
                d['enabled'] == false
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
              ),
              label: Text(
                d['enabled'] == false ? 'Resume hotel' : 'Suspend hotel',
              ),
            ),
            CustomButton.outlineIcon(
              onPressed: _detailBusy ? null : () => _deleteHotel(),
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: CustomColors.error,
              ),
              label: Text(_detailBusy ? 'Please wait…' : 'Delete hotel'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hotel information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 40,
                runSpacing: 14,
                children: [
                  _info('Owner', '${d['ownerName'] ?? ''}'),
                  _info('Address', '${d['address'] ?? ''}'),
                  _info('Created', adminDate(d['createdAt'])),
                  _info(
                    'Trial ends',
                    adminDate(adminMap(d['license'])['trialEndsAt']),
                  ),
                  _info(
                    'Membership expires',
                    adminDate(adminMap(d['license'])['expiresAt']),
                  ),
                  _info(
                    'Plan',
                    adminPlanLine(adminMap(d['license'])).isEmpty
                        ? 'No paid plan yet'
                        : adminPlanLine(adminMap(d['license'])),
                  ),
                  _info('Guests', '${d['guests']}'),
                  _info('Hotel ID', '${d['hotelId']}'),
                  _info(
                    'GST number',
                    '${adminMap(d['settings'])['hotel_gst_number'] ?? ''}',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Hotel analytics',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            for (final period in [
              (30, '30 days'),
              (90, '90 days'),
              (365, '1 year'),
              (0, 'All time'),
            ])
              ChoiceChip(
                label: Text(period.$2),
                selected: _days == period.$1,
                onSelected: _detailBusy
                    ? null
                    : (_) {
                        _days = period.$1;
                        _openHotel(d);
                      },
              ),
          ],
        ),
        const SizedBox(height: 16),
        AdminMetricGrid(
          children: [
            AdminMetric(
              title: 'Completed bills',
              value: adminMoney(stats['billed']),
              icon: Icons.receipt_long_outlined,
              note: '${stats['completedStays']} completed stays',
            ),
            AdminMetric(
              title: 'Expenses',
              value: adminMoney(stats['expenses']),
              icon: Icons.account_balance_wallet_outlined,
              note: 'Recorded in the selected period',
            ),
            AdminMetric(
              title: 'Billed minus expenses',
              value: adminMoney(stats['net']),
              icon: Icons.trending_up_rounded,
              note: 'Invoiced amount, not a bank balance',
            ),
            AdminMetric(
              title: 'Occupied rooms',
              value: '${rooms['booked']} / ${rooms['total']}',
              icon: Icons.bed_rounded,
              note: '${rooms['future']} future reservations',
            ),
          ],
        ),
        const SizedBox(height: 20),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionTitle(
                'Monthly billing & expenses',
                subtitle:
                    'Completed bills and recorded expenses · UTC reporting dates',
              ),
              AdminBarChart(series: series),
            ],
          ),
        ),
        const SizedBox(height: 28),
        AdminSectionTitle(
          'Hotel records',
          subtitle: 'Read directly from the shared Firebase backend',
          action: TextButton.icon(
            onPressed: _recordBusy ? null : _export,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Export loaded rows'),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _collections)
              ChoiceChip(
                label: Text(_labels[c]!),
                selected: _collection == c,
                onSelected: _recordBusy
                    ? null
                    : (_) {
                        setState(() {
                          _collection = c;
                          _records.clear();
                          _recordCursor = null;
                        });
                        _loadRecords();
                      },
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (_recordBusy) const LinearProgressIndicator(),
        if (_records.isEmpty && !_recordBusy)
          const AdminCard(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text('No records in this section.'),
            ),
          )
        else
          _recordTable(),
        if (_recordCursor != null)
          TextButton(
            onPressed: _recordBusy ? null : () => _loadRecords(more: true),
            child: const Text('Load more records'),
          ),
      ],
    );
  }

  Widget _info(String label, String value) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 150, maxWidth: 350),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: CustomColors.muted),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value.isEmpty ? '—' : value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );
  List<String> get _fields => switch (_collection) {
    'rooms' => [
      'roomNumber',
      'roomType',
      'status',
      'normalRent',
      'guestName',
      'futureBooking',
    ],
    'bookings' || 'futureBookings' => [
      'roomNumber',
      'guestName',
      'mobile',
      'bookingTime',
      'bookingDate',
      'status',
      'stayDurationMinutes',
    ],
    'guests' => ['guestName', 'mobile', 'idType', 'idNumber', 'address'],
    'bills' => [
      'billNumber',
      'guestName',
      'roomNumber',
      'totalBill',
      'discount',
      'checkoutTime',
      'stayDurationMinutes',
    ],
    'payments' => ['roomNumber', 'amount', 'paymentMode', 'kind', 'dateTime'],
    'expenses' => ['title', 'amount', 'paymentMode', 'dateTime'],
    'closedRooms' => ['roomNumber', 'roomType', 'faultReason'],
    'extraCharges' => ['roomNumber', 'title', 'amount', 'dateTime'],
    _ => ['id'],
  };
  String _label(String field) => field
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}')
      .replaceAll('id', 'ID');
  String _value(dynamic value) {
    if (value == null || value == '') return '—';
    if (value is Map || value is List) return jsonEncode(value);
    return '$value';
  }

  Widget _recordTable() => AdminCard(
    padding: EdgeInsets.zero,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: const WidgetStatePropertyAll(CustomColors.neutralTint),
        dataRowMaxHeight: 72,
        columns: [
          for (final f in _fields)
            DataColumn(
              label: Text(
                _label(f),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const DataColumn(label: Text('Details')),
        ],
        rows: [
          for (final r in _records)
            DataRow(
              cells: [
                for (final f in _fields)
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: Text(
                        f.toLowerCase().contains('time') ||
                                f.toLowerCase().contains('date')
                            ? adminDate(r[f])
                            : _value(r[f]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                DataCell(
                  IconButton(
                    tooltip: 'View record',
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    onPressed: () => _showRecord(r),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
  Future<void> _showRecord(Map<String, dynamic> record) async {
    await showAdminDialog<void>(
      context: context,
      builder: (context) => AdminDialog(
        title: Text('${_labels[_collection]} · Record'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_collection == 'guests') ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final side in ['Front', 'Back'])
                    CustomButton.outlineIcon(
                      onPressed: () {
                        final path =
                            record['id${side}StoragePath'] ??
                            adminMap(
                              record['id${side}PhotoPath'],
                            )['storagePath'];
                        if (path is! String || path.isEmpty) {
                          showAppToast(
                            context,
                            'No uploaded $side ID photo is available.',
                          );
                          return;
                        }
                        _photo(path, side);
                      },
                      icon: const Icon(Icons.badge_outlined),
                      label: Text('$side ID photo'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            for (final e in record.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label(e.key),
                      style: const TextStyle(
                        fontSize: 11,
                        color: CustomColors.muted,
                      ),
                    ),
                    SelectableText(
                      _value(e.value),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _photo(String path, String side) async {
    if (!path.startsWith('businesses/${_selected?['hotelId']}/guests/')) {
      showAppToast(
        context,
        'This photo does not belong to the selected hotel.',
      );
      return;
    }
    await showAdminDialog<void>(
      context: context,
      builder: (context) => AdminDialog(
        title: Text('$side ID photo'),
        content: FutureBuilder<Uint8List?>(
          // Served by the getGuestPhoto function, so the admin site needs
          // no Storage bucket CORS rule for its own domain.
          future: _api
              .call('getGuestPhoto', {'path': path})
              .then<Uint8List?>(
                (photo) => photo['base64'] is String
                    ? base64Decode(photo['base64'] as String)
                    : null,
              ),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(60),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || snapshot.data == null) {
              return const Text(
                'Photo could not be loaded. It may not have been uploaded yet.',
              );
            }
            return SizedBox(
              height: 420,
              child: InteractiveViewer(
                child: Image.memory(snapshot.data!, fit: BoxFit.contain),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    if (_records.isEmpty) {
      showAppToast(context, 'There are no loaded rows to export.');
      return;
    }
    String cell(dynamic value) {
      var text = _value(value);
      if (RegExp(r'^\s*[=+@\-]|^[\t\r]').hasMatch(text)) text = "'$text";
      return '"${text.replaceAll('"', '""')}"';
    }

    final fields = ['id', ..._fields.where((f) => f != 'id')];
    final csv = [
      fields.map(cell).join(','),
      ..._records.map((r) => fields.map((f) => cell(r[f])).join(',')),
    ].join('\r\n');
    try {
      await FileSaver.instance.saveFile(
        name: 'hotel-pro-$_collection',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
    } catch (e) {
      _fail(e);
    }
  }

  Widget _navigation(bool wide) => SizedBox(
    width: wide ? 244 : null,
    child: Material(
      color: CustomColors.primary,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(26, 32, 18, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIcon(
                    size: 34,
                    radius: 9,
                    color: CustomColors.onButton,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Hotel Pro',
                    style: TextStyle(
                      color: CustomColors.onButton,
                      fontSize: 25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'ADMIN WORKSPACE',
                    style: TextStyle(
                      color: CustomColors.bannerEnd,
                      fontSize: 9,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < _nav.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tileColor: _section == i
                      ? CustomColors.splashEnd
                      : CustomColors.transparent,
                  leading: Icon(
                    _nav[i].$2,
                    color: _section == i
                        ? CustomColors.onButton
                        : CustomColors.bannerEnd,
                    size: 21,
                  ),
                  title: Text(
                    _nav[i].$1,
                    style: TextStyle(
                      color: _section == i
                          ? CustomColors.onButton
                          : CustomColors.bannerEnd,
                      fontSize: 13,
                    ),
                  ),
                  onTap: () {
                    if (!wide) Navigator.pop(context);
                    _go(i);
                  },
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.email,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CustomColors.bannerEnd,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _busy ? null : widget.onSignOut,
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: const Text('Sign out'),
                    style: TextButton.styleFrom(
                      foregroundColor: CustomColors.onButton,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final content = _selected != null
        ? _hotelDetails()
        : switch (_section) {
            0 => _overview(),
            1 => _hotelsPage(),
            2 => _keysPage(),
            _ => _auditPage(),
          };
    return Scaffold(
      drawer: wide ? null : Drawer(child: _navigation(false)),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) _navigation(true),
            Expanded(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                    decoration: const BoxDecoration(
                      color: CustomColors.surface,
                      border: Border(
                        bottom: BorderSide(color: CustomColors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!wide)
                          Builder(
                            builder: (context) => IconButton(
                              tooltip: 'Open menu',
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                              icon: const Icon(Icons.menu_rounded),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selected != null
                                    ? 'Hotel details'
                                    : _nav[_section].$1,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _loadedAt == null
                                    ? 'Connected to Firebase'
                                    : 'Updated ${_loadedAt!.hour.toString().padLeft(2, '0')}:${_loadedAt!.minute.toString().padLeft(2, '0')} · Firebase',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: CustomColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh data',
                          onPressed: _busy || _detailBusy ? null : _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                        const SizedBox(width: 12),
                        const CircleAvatar(
                          backgroundColor: CustomColors.neutralTint,
                          child: Icon(
                            Icons.shield_outlined,
                            color: CustomColors.primary,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refresh,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.all(wide ? 32 : 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: CustomColors.error,
                                  ),
                                ),
                              ),
                            if (_busy && _hotels.isEmpty && _section < 2)
                              const Padding(
                                padding: EdgeInsets.all(70),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else
                              content,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteHotelDialog extends StatefulWidget {
  const _DeleteHotelDialog({required this.name});
  final String name;

  @override
  State<_DeleteHotelDialog> createState() => _DeleteHotelDialogState();
}

class _DeleteHotelDialogState extends State<_DeleteHotelDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminDialog(
    title: Text('Permanently delete ${widget.name}?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'This permanently removes the hotel and all its rooms, bookings, guest records, ID photos, bills, expenses, settings and membership. It will disappear from this list and cannot be restored. The owner can sign up again as a new hotel.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _typed,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Type DELETE to confirm',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Keep hotel'),
      ),
      CustomButton(
        style: FilledButton.styleFrom(backgroundColor: CustomColors.error),
        onPressed: _typed.text.trim() == 'DELETE'
            ? () => Navigator.pop(context, true)
            : null,
        child: const Text('Delete permanently'),
      ),
    ],
  );
}
