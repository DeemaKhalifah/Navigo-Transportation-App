import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:navigo/models/route.dart';
import 'package:navigo/models/schedule_slot.dart';
import 'package:navigo/services/google_route_path_service.dart';
import 'package:navigo/services/route_driver_queue_service.dart';
import 'package:navigo/services/route_manager_route_id.dart';
import 'package:navigo/services/schedule_slot_repository.dart';
import 'package:navigo/services/slot_driver_assignment_service.dart';

import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import 'add_schedule_slot_screen.dart';
import 'route_manager_nav_bar.dart';
import 'route_manager_notification_compose.dart';

class RouteSchedule extends StatefulWidget {
  const RouteSchedule({super.key});

  @override
  State<RouteSchedule> createState() => _RouteScheduleState();
}

class _RouteScheduleState extends State<RouteSchedule> {
  final ScheduleSlotRepository _repo = ScheduleSlotRepository();
  final RouteDriverQueueService _queueSvc = RouteDriverQueueService();
  final SlotDriverAssignmentService _slotAssign = SlotDriverAssignmentService();
  final GoogleRoutePathService _routePathService = GoogleRoutePathService();

  final Map<String, Future<String>> _driverLabelFutures = {};

  String _selectedType = 'bus';
  bool _autoAssignBusy = false;
  DateTime _lastAutoAssign = DateTime.fromMillisecondsSinceEpoch(0);
  bool _queueRefreshing = false;

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
      final snap =
          await FirebaseFirestore.instance.collection('route').doc(id).get();

      if (!mounted) return;

      if (snap.exists && snap.data() != null) {
        final data = Map<String, dynamic>.from(snap.data()!);
        data['routeId'] = data['routeId'] ?? id;

        setState(() {
          _route = RouteModel.fromMap(data);
          _loadingRoute = false;
        });

        unawaited(_syncRoutePath(id, _route!));

        // One-time queue sync only.
        // No repeated listener here because it caused heavy refreshing.
        unawaited(_queueSvc.syncQueueWithOnlineAvailableDrivers(id));

        return;
      }
    } catch (e) {
      debugPrint('RouteSchedule load route: $e');
    }

    if (!mounted) return;
    setState(() => _loadingRoute = false);
  }

  Future<void> _syncRoutePath(String routeId, RouteModel route) async {
    try {
      await _routePathService.syncRoutePathForRoute(
        routeId: routeId,
        startPoint: route.startPoint,
        endPoint: route.endPoint,
      );
    } catch (e) {
      debugPrint('RouteSchedule route path sync: $e');
    }
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
        SnackBar(content: Text(context.texts.t('tripUpdated'))),
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
    if (driverDocId.isEmpty) {
      return Future.value(context.texts.t('unassigned'));
    }

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

  Future<void> _autoAssignNow() async {
    final id = _routeId;
    if (id == null) return;
    if (_autoAssignBusy) return;

    final now = DateTime.now();

    if (now.difference(_lastAutoAssign) < const Duration(seconds: 3)) {
      return;
    }

    _lastAutoAssign = now;
    _autoAssignBusy = true;

    try {
      await _slotAssign.autoAssignUpcomingUnassignedSlots(routeId: id);
    } catch (e) {
      debugPrint('Auto-assign failed: $e');
    } finally {
      _autoAssignBusy = false;
    }
  }

  Future<void> _refreshQueueNow(String routeId) async {
    if (_queueRefreshing) return;

    setState(() => _queueRefreshing = true);

    try {
      await _queueSvc.syncQueueWithOnlineAvailableDrivers(routeId);
      await _autoAssignNow();
    } catch (e) {
      debugPrint('Queue refresh failed: $e');
    } finally {
      if (mounted) {
        setState(() => _queueRefreshing = false);
      }
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
                          context.texts.t('driverQueue'),
                          style: NavigoTextStyles.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed:
                            _queueRefreshing ? null : () => _refreshQueueNow(rid),
                        icon: _queueRefreshing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        color: NavigoColors.accentGreen,
                        tooltip: 'Refresh queue',
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

  String _routeTitle() {
    final r = _route;
    if (r == null) return context.texts.t('routeSchedule');
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

  bool _matchesSelectedType(String rawVehicleType) {
    final normalized = rawVehicleType
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), '');

    if (_selectedType == 'bus') {
      return normalized == 'bus';
    }

    if (_selectedType == 'micro') {
      return normalized == 'micro' || normalized == 'microbus';
    }

    return false;
  }

  String _vehicleTypeLabel(ScheduleSlot slot) {
    final raw = slot.vehicleType.trim();

    final normalized = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), '');

    if (normalized == 'bus') return context.texts.t('bus');

    if (normalized == 'micro' || normalized == 'microbus') {
      return context.texts.t('microBus');
    }

    return raw.isEmpty ? context.texts.t('bus') : raw;
  }

  Widget _buildDriverQueuePanel(String routeId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Queue is automatic: online + available drivers are appended. '
          'New trips are assigned to eligible drivers in FIFO order.',
          style: NavigoTextStyles.bodySmall.copyWith(fontSize: 11),
        ),
        const SizedBox(height: 10),

        // FIXED:
        // No FutureBuilder here.
        // No auto refresh when queue is empty.
        // Only refresh when user presses refresh button.

        StreamBuilder<List<String>>(
          stream: _queueSvc.watchQueueIds(routeId),
          builder: (context, qSnap) {
            final ids = qSnap.data ?? [];

            if (ids.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  context.texts.t('queueEmpty'),
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
                    backgroundColor: NavigoColors.accentGreen.withValues(
                      alpha: 0.15,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: NavigoTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: FutureBuilder<String>(
                    future: _driverLabelFuture(id),
                    builder: (c, s) {
                      return Text(
                        s.data ?? '…',
                        style: NavigoTextStyles.bodySmall,
                      );
                    },
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSlotCard(ScheduleSlot slot) {
    final dateLabel =
        '${slot.serviceDate.day}/${slot.serviceDate.month}/${slot.serviceDate.year}';

    return Dismissible(
      key: ValueKey(slot.slotId),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.texts.t('deleteTrip')),
            content: Text(context.texts.t('removeTripConfirm')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.texts.t('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Delete',
                  style: TextStyle(color: NavigoColors.accentRed),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        final id = _routeId;
        if (id == null) return;

        try {
          await _repo.deleteSlot(id, slot.slotId);

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.texts.t('tripRemoved'))),
          );
        } catch (e) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not delete: $e')),
          );
        }
      },
      background: Container(
        decoration: BoxDecoration(
          color: NavigoColors.accentRed,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: NavigoDecorations.kCardDecoration,
        child: Row(
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          _timeRange(slot),
                          style: NavigoTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _openSlotEditor(existing: slot),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.edit_outlined,
                            size: 20,
                            color: NavigoColors.primaryOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  NavigoDecorations.statusChip(
                    label: _vehicleTypeLabel(slot),
                    color: NavigoColors.primaryOrange,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
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
                          (slot.driverId.isEmpty ? 'Unassigned' : 'Driver…');

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
          ],
        ),
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
                title: context.texts.t('routeManager'),
                subtitle: _routeTitle(),
                avatar: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: NavigoDecorations.kTopBarBackButton,
                      child: IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const RouteManagerNotificationCompose(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: NavigoColors.surfaceWhite,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            width: 40,
                            height: 40,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _filterChip('bus', context.texts.t('bus')),
                  const SizedBox(width: 8),
                  _filterChip('micro', context.texts.t('microBus')),
                  const Spacer(),
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

                  // FIXED:
                  // Do NOT auto assign here.
                  // This StreamBuilder rebuilds many times and caused repeated loading.

                  final filtered = snapshot.data!
                      .where((s) => _matchesSelectedType(s.vehicleType))
                      .toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        context.texts.t('noTripsForType'),
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
                      child: Text(
                        context.texts.t('addTrip'),
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