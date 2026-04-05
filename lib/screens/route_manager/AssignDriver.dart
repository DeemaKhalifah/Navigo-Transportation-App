import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:navigo/models/driver_status.dart';
import 'package:navigo/models/trip.dart';
import 'package:navigo/screens/route_manager/RouteSchedule.dart';
import 'package:navigo/services/manual_driver_assignment_service.dart';
import 'package:navigo/services/route_manager_route_id.dart';
import 'package:navigo/theme/app_theme.dart';

import 'RouteManagerNavBar.dart';

class _DriverRow {
  _DriverRow({
    required this.driverId,
    required this.userId,
    required this.name,
    required this.vehicleLabel,
    required this.routeLine,
    required this.rawStatus,
  });

  final String driverId;
  final String userId;
  final String name;
  final String vehicleLabel;
  final String routeLine;

  /// Canonical: [DriverStatus.offline] | [DriverStatus.available] | [DriverStatus.onTrip]
  final String rawStatus;

  String get statusLabel {
    switch (rawStatus) {
      case DriverStatus.available:
        return 'Available';
      case DriverStatus.onTrip:
        return 'On Trip';
      case DriverStatus.offline:
        return 'Offline';
      default:
        return rawStatus;
    }
  }
}

class AssignDriver extends StatefulWidget {
  const AssignDriver({super.key});

  @override
  State<AssignDriver> createState() => _AssignDriverState();
}

class _AssignDriverState extends State<AssignDriver> {
  final ManualDriverAssignmentService _assignment = ManualDriverAssignmentService();

  String selectedFilter = 'All';
  String? _routeId;
  String _routeLine = 'Route';
  String? _loadError;
  bool _loading = true;
  List<_DriverRow> _drivers = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _driversSub;

  @override
  void initState() {
    super.initState();
    unawaited(_attach());
  }

  @override
  void dispose() {
    _driversSub?.cancel();
    super.dispose();
  }

  /// Loads managed route + subscribes to `drivers` where `routeId` matches (live updates).
  Future<void> _attach() async {
    await _driversSub?.cancel();
    _driversSub = null;

    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final routeId = await resolveManagedRouteId();
      if (!mounted) return;

      if (routeId == null || routeId.isEmpty) {
        setState(() {
          _routeId = null;
          _drivers = [];
          _loadError =
              'No route linked to this account. Set routeId on users or route_manager.';
          _loading = false;
        });
        return;
      }

      _routeId = routeId;

      final routeSnap =
          await FirebaseFirestore.instance.collection('route').doc(routeId).get();
      if (!mounted) return;

      if (routeSnap.exists) {
        final m = routeSnap.data();
        final a = m?['startPoint'] ?? '';
        final b = m?['endPoint'] ?? '';
        if (a.toString().isNotEmpty || b.toString().isNotEmpty) {
          _routeLine = '$a → $b';
        } else {
          _routeLine = 'Route';
        }
      }

      _driversSub = FirebaseFirestore.instance
          .collection('drivers')
          .where('routeId', isEqualTo: routeId)
          .snapshots()
          .listen(
            (snap) async {
              await _handleDriverSnapshot(snap.docs);
            },
            onError: (Object e, StackTrace st) {
              debugPrint('AssignDriver stream: $e\n$st');
              if (mounted) {
                setState(() {
                  _loadError = e.toString();
                  _loading = false;
                });
              }
            },
          );
    } catch (e, st) {
      debugPrint('AssignDriver attach: $e\n$st');
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleDriverSnapshot(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    try {
      if (docs.isEmpty) {
        if (mounted) {
          setState(() {
            _drivers = [];
            _loading = false;
          });
        }
        return;
      }

      final rows = await _buildRows(docs, _routeLine);
      if (!mounted) return;
      setState(() {
        _drivers = rows;
        _loading = false;
        _loadError = null;
      });
    } catch (e, st) {
      debugPrint('AssignDriver enrich: $e\n$st');
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<List<_DriverRow>> _buildRows(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String routeLine,
  ) async {
    final fs = FirebaseFirestore.instance;

    final userRefs = <String, DocumentReference<Map<String, dynamic>>>{};
    final vehicleRefs = <String, DocumentReference<Map<String, dynamic>>>{};

    for (final d in docs) {
      final data = d.data();
      final uid = data['userId'] as String? ?? d.id;
      userRefs[uid] = fs.collection('users').doc(uid);
      final vid = data['vehicleId'] as String?;
      if (vid != null && vid.isNotEmpty) {
        vehicleRefs[vid] = fs.collection('vehicles').doc(vid);
      }
    }

    final userSnaps = userRefs.isEmpty
        ? <DocumentSnapshot<Map<String, dynamic>>>[]
        : await Future.wait(userRefs.values.map((r) => r.get()));
    final vehicleSnaps = vehicleRefs.isEmpty
        ? <DocumentSnapshot<Map<String, dynamic>>>[]
        : await Future.wait(vehicleRefs.values.map((r) => r.get()));

    final userByUid = <String, Map<String, dynamic>?>{};
    for (final s in userSnaps) {
      userByUid[s.id] = s.data();
    }
    final vehicleById = <String, Map<String, dynamic>?>{};
    for (final s in vehicleSnaps) {
      vehicleById[s.id] = s.data();
    }

    final rows = <_DriverRow>[];
    for (final d in docs) {
      final data = d.data();
      final uid = data['userId'] as String? ?? d.id;
      final u = userByUid[uid];
      final first = u?['firstName'] ?? '';
      final last = u?['lastName'] ?? '';
      final name = '$first $last'.trim();
      final displayName = name.isEmpty ? 'Driver ${d.id.substring(0, 6)}' : name;

      final vid = data['vehicleId'] as String? ?? '';
      String vehicleLabel = vid.isEmpty ? 'No vehicle' : 'Vehicle: $vid';
      if (vid.isNotEmpty) {
        final vm = vehicleById[vid];
        if (vm != null) {
          final plate = vm['plateNumber'] ?? '';
          final type = vm['type'] ?? '';
          vehicleLabel = [type, plate].where((e) => e.toString().isNotEmpty).join(' · ');
          if (vehicleLabel.isEmpty) vehicleLabel = 'Vehicle: $vid';
        }
      }

      final normalized = DriverStatus.normalize(data['status'] as String?);

      rows.add(
        _DriverRow(
          driverId: d.id,
          userId: uid,
          name: displayName,
          vehicleLabel: vehicleLabel,
          routeLine: routeLine,
          rawStatus: normalized,
        ),
      );
    }

    rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  List<_DriverRow> get filteredDrivers {
    if (selectedFilter == 'All') return _drivers;
    return _drivers.where((d) {
      switch (selectedFilter) {
        case 'Available':
          return d.rawStatus == DriverStatus.available;
        case 'On Trip':
          return d.rawStatus == DriverStatus.onTrip;
        case 'Offline':
          return d.rawStatus == DriverStatus.offline;
        default:
          return true;
      }
    }).toList();
  }

  Future<List<Trip>> _upcomingTripsForRoute() async {
    final routeId = _routeId;
    if (routeId == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection('trips')
        .where('routeId', isEqualTo: routeId)
        .get();

    final now = DateTime.now();
    final trips = snap.docs
        .map((d) => Trip.fromMap(d.id, d.data()))
        .where((t) => t.departureAt.isAfter(now.subtract(const Duration(minutes: 1))))
        .toList()
      ..sort((a, b) => a.departureAt.compareTo(b.departureAt));
    return trips;
  }

  Future<void> _onAssign(_DriverRow driver) async {
    final routeId = _routeId;
    if (routeId == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    List<Trip> trips;
    try {
      trips = await _upcomingTripsForRoute();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }

    if (!mounted) return;

    if (trips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No upcoming trips on this route to assign.'),
        ),
      );
      return;
    }

    final chosen = await showDialog<Trip>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Assign to trip'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: trips.length,
            itemBuilder: (_, i) {
              final t = trips[i];
              final start = t.departureAt;
              return ListTile(
                title: Text(
                  '${start.day}/${start.month}/${start.year} '
                  '${start.hour.toString().padLeft(2, '0')}:'
                  '${start.minute.toString().padLeft(2, '0')}',
                ),
                subtitle: Text('Trip ${t.tripId.substring(0, 8)}… · slot ${t.slotId}'),
                onTap: () => Navigator.pop(ctx, t),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (chosen == null || !mounted) return;

    try {
      await _assignment.assignDriverToTrip(
        routeId: routeId,
        tripId: chosen.tripId,
        newDriverId: driver.driverId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver assigned to trip.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Assignment failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RouteSchedule()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NavigoSizes.screenPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Assignments', style: NavigoTextStyles.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Drivers on your route (status from drivers collection)',
                    style: NavigoTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: NavigoSizes.sectionGap),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NavigoSizes.screenPadding,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Available', 'On Trip', 'Offline']
                      .map(
                        (label) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: NavigoDecorations.selectorChip(
                            label: label,
                            selected: selectedFilter == label,
                            onTap: () => setState(() => selectedFilter = label),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: NavigoSizes.sectionGap),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _loadError!,
                              textAlign: TextAlign.center,
                              style: NavigoTextStyles.bodyMedium,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _attach,
                          child: filteredDrivers.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: const [
                                    SizedBox(height: 120),
                                    Center(
                                      child: Text('No drivers for this route.'),
                                    ),
                                  ],
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: NavigoSizes.screenPadding,
                                  ),
                                  itemCount: filteredDrivers.length,
                                  itemBuilder: (context, index) {
                                    final driver = filteredDrivers[index];
                                    return Container(
                                      margin: const EdgeInsets.only(
                                        bottom: NavigoSizes.itemGap,
                                      ),
                                      padding: const EdgeInsets.all(
                                        NavigoSizes.cardPadding,
                                      ),
                                      decoration: NavigoDecorations.kCardDecoration,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  driver.name,
                                                  style: NavigoTextStyles.titleSmall,
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  driver.vehicleLabel,
                                                  style: NavigoTextStyles.bodyMedium,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Route: ${driver.routeLine}',
                                                  style: NavigoTextStyles.label,
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              _statusChip(driver.statusLabel),
                                              if (driver.rawStatus ==
                                                  DriverStatus.available) ...[
                                                const SizedBox(height: 8),
                                                ElevatedButton(
                                                  onPressed: () =>
                                                      _onAssign(driver),
                                                  style: NavigoDecorations
                                                      .kPrimaryButtonLargeStyle
                                                      .copyWith(
                                                    padding:
                                                        const WidgetStatePropertyAll(
                                                      EdgeInsets.symmetric(
                                                        horizontal: 24,
                                                        vertical: 10,
                                                      ),
                                                    ),
                                                    elevation:
                                                        const WidgetStatePropertyAll(
                                                      4,
                                                    ),
                                                    shadowColor:
                                                        WidgetStatePropertyAll(
                                                      NavigoColors.primaryOrange
                                                          .withValues(alpha: 0.4),
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    'Assign',
                                                    style: NavigoTextStyles.button,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const RouteManagerNavBar(currentIndex: 1),
    );
  }

  Widget _statusChip(String status) {
    final Color color;

    switch (status) {
      case 'Available':
        color = NavigoColors.accentGreen;
        break;
      case 'On Trip':
        color = NavigoColors.accentBlue;
        break;
      case 'Offline':
        color = NavigoColors.accentRed;
        break;
      default:
        color = NavigoColors.textMuted;
    }

    return NavigoDecorations.statusChip(label: status, color: color);
  }
}
