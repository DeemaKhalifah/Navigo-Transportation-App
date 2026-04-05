import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:navigo/models/driver_status.dart';
import 'package:navigo/models/route.dart';
import 'package:navigo/models/schedule_slot.dart';
import 'package:navigo/services/route_manager_route_id.dart';
import 'package:navigo/services/route_driver_queue_service.dart';
import 'package:navigo/services/schedule_slot_repository.dart';
import 'package:navigo/services/slot_driver_assignment_service.dart';
import 'AddScheduleSlotScreen.dart';
import 'RouteManagerNavBar.dart';
import '../../theme/app_theme.dart';

class RouteSchedule extends StatefulWidget {
  const RouteSchedule({super.key});

  @override
  State<RouteSchedule> createState() => _RouteScheduleState();
}

class _RouteScheduleState extends State<RouteSchedule> {
  final ScheduleSlotRepository _repo = ScheduleSlotRepository();
  final RouteDriverQueueService _queueSvc = RouteDriverQueueService();
  final SlotDriverAssignmentService _slotAssign = SlotDriverAssignmentService();

  final Map<String, Future<String>> _driverLabelFutures = {};

  String _selectedType = 'bus';
  bool _assignOneBusy = false;

  String? _routeId;
  RouteModel? _route;
  bool _loadingRoute = true;

  @override
  void initState() {
    super.initState();
    _loadRouteContext();
  }

  Future<void> _loadRouteContext() async {
    final id = await resolveManagedRouteId();
    if (!mounted) return;
    if (id == null || id.isEmpty) {
      setState(() {
        _routeId = null;
        _loadingRoute = false;
      });
      return;
    }

    setState(() => _routeId = id);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('route')
          .doc(id)
          .get();
      if (!mounted) return;
      if (snap.exists && snap.data() != null) {
        final data = Map<String, dynamic>.from(snap.data()!);
        data['routeId'] = data['routeId'] ?? id;
        setState(() {
          _route = RouteModel.fromMap(data);
          _loadingRoute = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('RouteSchedule load route: $e');
    }

    if (!mounted) return;
    setState(() => _loadingRoute = false);
  }

  Future<void> _openSlotEditor({ScheduleSlot? existing}) async {
    final id = _routeId;
    if (id == null) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddScheduleSlotScreen(
          routeId: id,
          existingSlot: existing,
        ),
      ),
    );

    if (result == true && mounted && existing != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip updated')),
      );
    }
  }

  Future<void> _confirmDelete(ScheduleSlot slot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete trip'),
        content: const Text(
          'Remove this trip from the schedule?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final id = _routeId;
    if (id == null) return;

    try {
      await _repo.deleteSlot(id, slot.slotId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip removed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    }
  }

  String _timeRange(ScheduleSlot s) {
    final a = TimeOfDay.fromDateTime(s.departureAt);
    if (s.vehicleType == 'micro') {
      return a.format(context);
    }
    final b = TimeOfDay.fromDateTime(s.arrivalAt);
    return '${a.format(context)} – ${b.format(context)}';
  }

  Future<String> _driverLabelFuture(String driverDocId) {
    if (driverDocId.isEmpty) return Future.value('Unassigned');
    return _driverLabelFutures.putIfAbsent(
      driverDocId,
      () => _loadDriverLabel(driverDocId),
    );
  }

  Future<String> _loadDriverLabel(String driverDocId) async {
    final fs = FirebaseFirestore.instance;
    final d = await fs.collection('drivers').doc(driverDocId).get();
    final uid = d.data()?['userId'] as String? ?? driverDocId;
    final u = await fs.collection('users').doc(uid).get();
    final m = u.data();
    final first = m?['firstName'] ?? '';
    final last = m?['lastName'] ?? '';
    final n = '$first $last'.trim();
    return n.isEmpty ? 'Driver ${driverDocId.substring(0, 6)}…' : n;
  }

  Future<void> _onQueueAllAvailable(String routeId) async {
    try {
      await _queueSvc.queueAllAvailableDriversSorted(routeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Queue set to all available drivers (A–Z).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not build queue: $e')),
      );
    }
  }

  Future<void> _assignOneFromQueue() async {
    final id = _routeId;
    if (id == null) return;
    setState(() => _assignOneBusy = true);
    try {
      final r = await _slotAssign.tryAssignFirstUnassignedSlot(
        routeId: id,
        vehicleType: _selectedType,
      );
      if (!mounted) return;
      if (r.outcome == SlotAssignmentOutcome.assigned) {
        final label = await _driverLabelFuture(r.driverId!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assigned $label to the next open trip.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No assignment: add an unassigned trip or drivers in the queue.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Assign failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _assignOneBusy = false);
    }
  }

  void _openDriverQueueBottomSheet() {
    final rid = _routeId;
    if (rid == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.viewPaddingOf(ctx).bottom;
        final maxH = MediaQuery.sizeOf(ctx).height * 0.72;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            height: maxH,
            decoration: BoxDecoration(
              color: NavigoColors.backgroundLight,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: NavigoColors.textMuted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Driver queue',
                          style: NavigoTextStyles.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                        color: NavigoColors.textMuted,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: _buildDriverQueuePanel(rid),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onClearQueue(String routeId) async {
    try {
      await _queueSvc.clearQueue(routeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver queue cleared.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear queue: $e')),
      );
    }
  }

  String _routeTitle() {
    final r = _route;
    if (r == null) return 'Route schedule';
    return '${r.startPoint} → ${r.endPoint}';
  }

  Widget _filterChip(String type, String label) {
    final selected = _selectedType == type;
    return NavigoDecorations.selectorChip(
      label: label,
      selected: selected,
      onTap: () => setState(() => _selectedType = type),
    );
  }

  /// Queue controls (used inside the bottom sheet).
  Widget _buildDriverQueuePanel(String routeId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            Text(
              'Use “queue all” or tap a driver to append. '
              'First in list is used for the next assignment.',
              style: NavigoTextStyles.bodySmall.copyWith(fontSize: 11),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _onClearQueue(routeId),
                    child: const Text('Clear queue'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _onQueueAllAvailable(routeId),
                    style: NavigoDecorations.kPrimaryButtonLargeStyle.copyWith(
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                    ),
                    child: const Text(
                      'Queue all available',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            StreamBuilder<List<String>>(
              stream: _queueSvc.watchQueueIds(routeId),
              builder: (context, qSnap) {
                final ids = qSnap.data ?? [];
                if (ids.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Queue is empty.',
                      style: NavigoTextStyles.bodySmall,
                    ),
                  );
                }
                return Column(
                  children: List.generate(ids.length, (i) {
                    final id = ids[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            NavigoColors.accentGreen.withValues(alpha: 0.15),
                        child: Text(
                          '${i + 1}',
                          style: NavigoTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: FutureBuilder<String>(
                        future: _driverLabelFuture(id),
                        builder: (c, s) => Text(
                          s.data ?? '…',
                          style: NavigoTextStyles.bodySmall,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => _queueSvc.removeDriver(routeId, id),
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Available drivers — tap to append',
              style: NavigoTextStyles.label,
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 44,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('drivers')
                    .where('routeId', isEqualTo: routeId)
                    .snapshots(),
                builder: (context, dSnap) {
                  if (!dSnap.hasData) {
                    return const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final docs = dSnap.data!.docs.where((d) {
                    final st = DriverStatus.normalize(
                      d.data()['status'] as String?,
                    );
                    return st == DriverStatus.available;
                  }).toList();

                  if (docs.isEmpty) {
                    return Text(
                      'No available drivers',
                      style: NavigoTextStyles.bodySmall,
                    );
                  }

                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      return ActionChip(
                        label: FutureBuilder<String>(
                          future: _driverLabelFuture(d.id),
                          builder: (c, s) => Text(
                            s.data ?? d.id.substring(0, 6),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        onPressed: () =>
                            _queueSvc.appendDriver(routeId, d.id),
                      );
                    },
                  );
                },
              ),
            ),
      ],
    );
  }

  Widget _buildSlotCard(ScheduleSlot slot) {
    final dateLabel =
        '${slot.serviceDate.day}/${slot.serviceDate.month}/${slot.serviceDate.year}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: NavigoDecorations.kCardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: NavigoDecorations.iconCircleDecoration(
                  NavigoColors.accentGreen.withOpacity(0.1),
                ),
                child: const Icon(
                  Icons.route,
                  color: NavigoColors.accentGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _timeRange(slot),
                      style: NavigoTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${slot.capacity} seats'
                      '${slot.price != null ? ' · ${slot.price} (override)' : ''}'
                      '${slot.frequencyMinutes != null && slot.frequencyMinutes! > 0 ? ' · every ${slot.frequencyMinutes} min' : ''}',
                      style: NavigoTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    FutureBuilder<String>(
                      future: _driverLabelFuture(slot.driverId),
                      builder: (context, snap) {
                        final t = snap.data ??
                            (slot.driverId.isEmpty
                                ? 'Unassigned'
                                : 'Driver…');
                        return Text(
                          'Driver: $t',
                          style: NavigoTextStyles.bodySmall.copyWith(
                            fontSize: 12,
                            color: NavigoColors.textMuted,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 13,
                          color: NavigoColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dateLabel,
                          style: NavigoTextStyles.bodySmall.copyWith(
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  NavigoDecorations.statusChip(
                    label: slot.vehicleType == 'bus' ? 'Bus' : 'Micro',
                    color: NavigoColors.primaryOrange,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _openSlotEditor(existing: slot),
                        child: const Text('Edit'),
                      ),
                      TextButton(
                        onPressed: () => _confirmDelete(slot),
                        child: Text(
                          'Delete',
                          style: NavigoTextStyles.bodySmall.copyWith(
                            color: NavigoColors.accentRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRoute) {
      return Scaffold(
        backgroundColor: NavigoColors.backgroundLight,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_routeId == null) {
      return Scaffold(
        backgroundColor: NavigoColors.backgroundLight,
        bottomNavigationBar: const RouteManagerNavBar(currentIndex: 0),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No route is linked to this account. Set `routeId` on '
                '`users/{uid}` or on `route_manager/{uid}`.',
                textAlign: TextAlign.center,
                style: NavigoTextStyles.bodyMedium,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const RouteManagerNavBar(currentIndex: 0),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: NavigoDecorations.homeStyleTitleBar(
                title: 'Route Manager',
                subtitle: _routeTitle(),
                avatar: CircleAvatar(
                  radius: 20,
                  backgroundColor: NavigoColors.surfaceWhite,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                        width: 30,
                        height: 30,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _filterChip('bus', 'Bus'),
                  const SizedBox(width: 8),
                  _filterChip('micro', 'Micro Bus'),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: NavigoColors.primaryOrange,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _assignOneBusy ? null : _assignOneFromQueue,
                    child: _assignOneBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Assign 1'),
                  ),
                  const SizedBox(width: 4),
                  Material(
                    color: NavigoColors.surfaceWhite,
                    elevation: 2,
                    shadowColor: Colors.black26,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _openDriverQueueBottomSheet,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.view_list_rounded,
                          size: 22,
                          color: NavigoColors.accentGreen,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: StreamBuilder<List<ScheduleSlot>>(
                stream: _repo.watchSlots(_routeId!),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: NavigoTextStyles.bodySmall,
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final filtered = snapshot.data!
                      .where((s) => s.vehicleType == _selectedType)
                      .toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        'No trips for this vehicle type',
                        style: NavigoTextStyles.bodySmall,
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (_, i) => _buildSlotCard(filtered[i]),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: NavigoSizes.buttonHeight,
                    child: ElevatedButton(
                      onPressed: () => _openSlotEditor(),
                      style: NavigoDecorations.kPrimaryButtonLargeStyle,
                      child: const Text(
                        'Add trip',
                        style: NavigoTextStyles.button,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
