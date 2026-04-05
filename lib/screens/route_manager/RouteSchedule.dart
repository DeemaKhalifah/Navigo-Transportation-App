import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:navigo/models/route.dart';
import 'package:navigo/models/schedule_slot.dart';
import 'package:navigo/services/route_manager_route_id.dart';
import 'package:navigo/services/schedule_slot_repository.dart';
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

  String _selectedType = 'bus';

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
        const SnackBar(content: Text('Slot updated')),
      );
    }
  }

  Future<void> _confirmDelete(ScheduleSlot slot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete slot'),
        content: const Text(
          'Remove this departure from the schedule?',
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
        const SnackBar(content: Text('Slot removed')),
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
    final b = TimeOfDay.fromDateTime(s.arrivalAt);
    return '${a.format(context)} – ${b.format(context)}';
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
                      '${slot.price != null ? ' · ${slot.price} (override)' : ''}',
                      style: NavigoTextStyles.bodySmall,
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
                children: [
                  _filterChip('bus', 'Bus'),
                  const SizedBox(width: 8),
                  _filterChip('micro', 'Micro Bus'),
                ],
              ),
            ),
            const SizedBox(height: 12),
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
                        'No slots for this vehicle type',
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
                        'Add slot',
                        style: NavigoTextStyles.button,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: NavigoSizes.buttonHeight,
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Slots sync to Firestore automatically.',
                            ),
                          ),
                        );
                      },
                      style: NavigoDecorations.kPrimaryButtonLargeStyle.copyWith(
                        backgroundColor: const WidgetStatePropertyAll(
                          NavigoColors.accentGreen,
                        ),
                      ),
                      child: const Text('Publish updates'),
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
