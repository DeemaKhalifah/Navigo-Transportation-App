import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:navigo/models/driver_status.dart';
import 'package:navigo/screens/route_manager/route_schedule.dart';
import 'package:navigo/services/route_manager_route_id.dart';
import 'package:navigo/theme/app_theme.dart';
import '../../localization/localization_x.dart';
import '../../modules/driver/driver_row.dart';
import '../../services/route_driver_queue_service.dart';

import 'route_manager_notification_compose.dart';
import 'route_manager_nav_bar.dart';

class AssignDriver extends StatefulWidget {
  const AssignDriver({super.key});

  @override
  State<AssignDriver> createState() => _AssignDriverState();
}

class _AssignDriverState extends State<AssignDriver> {
  final RouteDriverQueueService _queueSvc = RouteDriverQueueService();

  String selectedFilter = 'All';
  String _routeLine = 'Route';
  String? _loadError;
  bool _loading = true;
  List<DriverRow> _drivers = [];
  List<String> _queueIds = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _driversSub;
  StreamSubscription<List<String>>? _queueSub;

  @override
  void initState() {
    super.initState();
    unawaited(_attach());
  }

  @override
  void dispose() {
    _driversSub?.cancel();
    _queueSub?.cancel();
    super.dispose();
  }

  /// Loads managed route + subscribes to `drivers` where `routeId` matches (live updates).
  Future<void> _attach() async {
    await _driversSub?.cancel();
    _driversSub = null;
    await _queueSub?.cancel();
    _queueSub = null;

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
          _drivers = [];
          _loadError = context.texts.t('noRouteLinkedAccount');
          _loading = false;
        });
        return;
      }

      _queueSub = _queueSvc.watchQueueIds(routeId).listen((ids) {
        if (!mounted) return;
        setState(() => _queueIds = ids);
      });
      unawaited(_queueSvc.syncQueueWithOnlineAvailableDrivers(routeId));

      final routeSnap = await FirebaseFirestore.instance
          .collection('route')
          .doc(routeId)
          .get();
      if (!mounted) return;

      if (routeSnap.exists) {
        final m = routeSnap.data();
        final a = m?['startPoint'] ?? '';
        final b = m?['endPoint'] ?? '';
        if (a.toString().isNotEmpty || b.toString().isNotEmpty) {
          _routeLine = '$a → $b';
        } else {
          _routeLine = context.texts.t('route');
        }
      }

      _driversSub = FirebaseFirestore.instance
          .collection('drivers')
          .where('routeId', isEqualTo: routeId)
          .snapshots()
          .listen(
            (snap) async {
              // Prune queue immediately when driver eligibility changes.
              unawaited(_queueSvc.syncQueueWithOnlineAvailableDrivers(routeId));
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

      final texts = context.texts;
      final rows = await _buildRows(
        docs,
        _routeLine,
        driverLabel: texts.t('driver'),
        noVehicleLabel: texts.t('noVehicle'),
        vehicleLabel: texts.t('vehicle'),
      );
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

  Future<List<DriverRow>> _buildRows(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String routeLine, {
    required String driverLabel,
    required String noVehicleLabel,
    required String vehicleLabel,
  }) async {
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

    final rows = <DriverRow>[];
    for (final d in docs) {
      final data = d.data();
      final uid = data['userId'] as String? ?? d.id;
      final u = userByUid[uid];
      final first = u?['firstName'] ?? '';
      final last = u?['lastName'] ?? '';
      final name = '$first $last'.trim();
      final displayName = name.isEmpty
          ? '$driverLabel ${d.id.substring(0, 6)}'
          : name;

      final vid = data['vehicleId'] as String? ?? '';
      String vehicleDisplay = vid.isEmpty
          ? noVehicleLabel
          : '$vehicleLabel: $vid';
      if (vid.isNotEmpty) {
        final vm = vehicleById[vid];
        if (vm != null) {
          final plate = vm['plateNumber'] ?? '';
          final type = vm['type'] ?? '';
          vehicleDisplay = [
            type,
            plate,
          ].where((e) => e.toString().isNotEmpty).join(' · ');
          if (vehicleDisplay.isEmpty) {
            vehicleDisplay = '$vehicleLabel: $vid';
          }
        }
      }

      final normalized = DriverStatus.normalize(data['status'] as String?);
      final isOnline = data['isOnline'] == true;

      rows.add(
        DriverRow(
          driverId: d.id,
          userId: uid,
          name: displayName,
          vehicleLabel: vehicleDisplay,
          routeLine: routeLine,
          rawStatus: normalized,
          isOnline: isOnline,
        ),
      );
    }

    rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  List<DriverRow> get filteredDrivers {
    if (selectedFilter == 'All') return _drivers;
    return _drivers.where((d) {
      switch (selectedFilter) {
        case 'Available':
          return d.isOnline && d.rawStatus == DriverStatus.available;
        case 'Assigned':
          return d.rawStatus == DriverStatus.assigned;
        case 'On Trip':
          return d.rawStatus == DriverStatus.onTrip;
        case 'Offline':
          return !d.isOnline || d.rawStatus == DriverStatus.offline;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filters = {
      'All': context.texts.t('all'),
      'Available': context.texts.t('available'),
      'Assigned': context.texts.t('assigned'),
      'On Trip': context.texts.t('onTrip'),
      'Offline': context.texts.t('offline'),
    };

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar3(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RouteSchedule()),
              ),
              onNotification: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RouteManagerNotificationCompose(),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NavigoSizes.screenPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.texts.t('driverStatus'),
                    style: NavigoTextStyles.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.texts.t('driverStatusSubtitle'),
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
                  children: filters.entries
                      .map(
                        (filter) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: NavigoDecorations.selectorChip(
                            label: filter.value,
                            selected: selectedFilter == filter.key,
                            onTap: () =>
                                setState(() => selectedFilter = filter.key),
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
                              children: [
                                SizedBox(height: 120),
                                Center(
                                  child: Text(
                                    context.texts.t('noDriversForRoute'),
                                  ),
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
                                final pos = _queueIds.indexOf(driver.driverId);
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
                                              style:
                                                  NavigoTextStyles.titleSmall,
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              driver.vehicleLabel,
                                              style:
                                                  NavigoTextStyles.bodyMedium,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${context.texts.t('route')}: ${driver.routeLine}',
                                              style: NavigoTextStyles.label,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              pos >= 0
                                                  ? '${context.texts.t('queuePosition')}: ${pos + 1}'
                                                  : context.texts.t(
                                                      'notInQueue',
                                                    ),
                                              style: NavigoTextStyles.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          _statusChip(
                                            driver.rawStatus,
                                            driver.isOnline,
                                          ),
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

  Widget _statusChip(String rawStatus, bool isOnline) {
    final Color color;
    final String label;

    switch (rawStatus) {
      case DriverStatus.available:
        label = isOnline
            ? context.texts.t('available')
            : context.texts.t('offline');
        color = isOnline ? NavigoColors.accentGreen : NavigoColors.accentRed;
        break;
      case DriverStatus.assigned:
        label = context.texts.t('assigned');
        color = NavigoColors.primaryOrange;
        break;
      case DriverStatus.onTrip:
        label = context.texts.t('onTrip');
        color = NavigoColors.accentBlue;
        break;
      case DriverStatus.offline:
        label = context.texts.t('offline');
        color = NavigoColors.accentRed;
        break;
      default:
        label = rawStatus;
        color = NavigoColors.textMuted;
    }

    return NavigoDecorations.statusChip(label: label, color: color);
  }
}
