import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../controllers/app_controller_scope.dart';
import '../models/admin_dashboard_model.dart';
import '../localization/localization_x.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_dashboard_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_account_dialog.dart';
import 'admin_login_screen.dart';

enum _AdminSection {
  dashboard,
  drivers,
  routes,
  routeManagers,
  trips,
  passengers,
  reports,
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminDashboardService _service = AdminDashboardService();
  final Set<String> _busyApprovalIds = {};
  _AdminSection _selectedSection = _AdminSection.dashboard;
  bool _isLoggingOut = false;

  Future<void> _logoutAdmin() async {
    if (_isLoggingOut) return;

    try {
      setState(() {
        _isLoggingOut = true;
      });

      await AdminAuthService().logout();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.texts.t('loggedOutSuccessfully'))),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  Future<void> _approveDriver(AdminApprovalItem item) async {
    await _runApprovalAction(
      item: item,
      successMessage: '${item.name} ${context.texts.t('approved')}',
      action: () => _service.approveDriver(item),
    );
  }

  Future<void> _rejectDriver(AdminApprovalItem item) async {
    await _runApprovalAction(
      item: item,
      successMessage: '${item.name} ${context.texts.t('rejected')}',
      action: () => _service.rejectDriver(item),
    );
  }

  Future<void> _runApprovalAction({
    required AdminApprovalItem item,
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    if (_busyApprovalIds.contains(item.id)) return;

    setState(() => _busyApprovalIds.add(item.id));
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.texts.t('couldNotUpdateDriver')}: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyApprovalIds.remove(item.id));
      }
    }
  }

  void _showDashboard() {
    setState(() => _selectedSection = _AdminSection.dashboard);
  }

  void _showReports() {
    setState(() => _selectedSection = _AdminSection.reports);
  }

  void _showDrivers() {
    setState(() => _selectedSection = _AdminSection.drivers);
  }

  void _showRoutes() {
    setState(() => _selectedSection = _AdminSection.routes);
  }

  void _showRouteManagers() {
    setState(() => _selectedSection = _AdminSection.routeManagers);
  }

  void _showPassengers() {
    setState(() => _selectedSection = _AdminSection.passengers);
  }

  void _showTrips() {
    setState(() => _selectedSection = _AdminSection.trips);
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: Row(
        children: [
          _Sidebar(
            selectedSection: _selectedSection,
            isLoggingOut: _isLoggingOut,
            onDashboard: _showDashboard,
            onDrivers: _showDrivers,
            onRoutes: _showRoutes,
            onRouteManagers: _showRouteManagers,
            onTrips: _showTrips,
            onPassengers: _showPassengers,
            onReports: _showReports,
            onLogout: _logoutAdmin,
          ),
          Expanded(
            child: _selectedSection == _AdminSection.reports
                ? _ReportsPanel(service: _service)
                : _selectedSection == _AdminSection.drivers
                ? _DriversPanel(service: _service)
                : _selectedSection == _AdminSection.routes
                ? _RoutesPanel(service: _service)
                : _selectedSection == _AdminSection.routeManagers
                ? _RouteManagersPanel(service: _service)
                : _selectedSection == _AdminSection.trips
                ? _TripsPanel(service: _service)
                : _selectedSection == _AdminSection.passengers
                ? _PassengersPanel(service: _service)
                : StreamBuilder<AdminDashboardModel>(
                    stream: _service.dashboardStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            '${texts.t('errorLoadingDashboard')}: ${snapshot.error}',
                          ),
                        );
                      }

                      final data = snapshot.data;

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 24, 16),
                        child: Container(
                          decoration: _cardDecoration(
                            radius: 28,
                          ).copyWith(color: NavigoColors.surfaceWhite),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(34),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _Header(),
                                const SizedBox(height: 34),
                                GridView(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 240,
                                        mainAxisExtent: 210,
                                        crossAxisSpacing: 22,
                                        mainAxisSpacing: 22,
                                      ),
                                  children: [
                                    _StatCard(
                                      title: texts.t('totalUsers'),
                                      value: data?.totalUsers.toString() ?? '0',
                                      label: texts.t('allUsers'),
                                      icon: Icons.groups_rounded,
                                      color: NavigoColors.accentBlue,
                                    ),
                                    _StatCard(
                                      title: texts.t('activeRoutes'),
                                      value:
                                          data?.totalRoutes.toString() ?? '0',
                                      label: texts.t('availableRoutes'),
                                      icon: Icons.route_rounded,
                                      color: NavigoColors.accentGreen,
                                      onTap: _showRoutes,
                                    ),
                                    _StatCard(
                                      title: texts.t('activeTrips'),
                                      value:
                                          data?.activeTrips.toString() ?? '0',
                                      label: texts.t('onGoing'),
                                      icon: Icons.directions_bus_rounded,
                                      color: NavigoColors.primaryOrange,
                                      onTap: _showTrips,
                                    ),
                                    _StatCard(
                                      title: texts.t('drivers'),
                                      value:
                                          data?.totalDrivers.toString() ?? '0',
                                      label:
                                          '${data?.pendingDrivers ?? 0} ${texts.t('pendingReview')}',
                                      icon: Icons.local_taxi_rounded,
                                      color: Colors.purple,
                                      onTap: _showDrivers,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                GridView(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 300,
                                        mainAxisExtent: 138,
                                        crossAxisSpacing: 22,
                                        mainAxisSpacing: 22,
                                      ),
                                  children: [
                                    _ActionCard(
                                      title: texts.t('driversApproval'),
                                      subtitle: texts.t(
                                        'reviewAndApproveDrivers',
                                      ),
                                      icon: Icons.verified_user_rounded,
                                      color: NavigoColors.accentGreen,
                                      onTap: _showDrivers,
                                    ),
                                    _ActionCard(
                                      title: texts.t('tripsManagement'),
                                      subtitle: texts.t('manageAllTrips'),
                                      icon: Icons.directions_bus_rounded,
                                      color: NavigoColors.primaryOrange,
                                      onTap: _showTrips,
                                    ),
                                    _ActionCard(
                                      title: texts.t('routesManagement'),
                                      subtitle: texts.t('manageAllRoutes'),
                                      icon: Icons.route_rounded,
                                      color: NavigoColors.accentBlue,
                                      onTap: _showRoutes,
                                    ),
                                    _ActionCard(
                                      title: texts.t('reportsAnalytics'),
                                      subtitle:
                                          '${data?.reports.length ?? 0} ${texts.t('adminReports')}',
                                      icon: Icons.bar_chart_rounded,
                                      color: Colors.purple,
                                      onTap: _showReports,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final stack = constraints.maxWidth < 860;
                                    final overview = _PieChartCard(
                                      totalDrivers: data?.totalDrivers ?? 0,
                                      pendingDrivers: data?.pendingDrivers ?? 0,
                                      totalUsers: data?.totalUsers ?? 0,
                                    );
                                    final approvals = _PendingApprovalsCard(
                                      approvals: data?.approvals ?? [],
                                      busyApprovalIds: _busyApprovalIds,
                                      onApprove: _approveDriver,
                                      onReject: _rejectDriver,
                                    );

                                    if (stack) {
                                      return Column(
                                        children: [
                                          overview,
                                          const SizedBox(height: 24),
                                          approvals,
                                        ],
                                      );
                                    }

                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(flex: 2, child: overview),
                                        const SizedBox(width: 24),
                                        Expanded(flex: 4, child: approvals),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DriversPanel extends StatefulWidget {
  final AdminDashboardService service;

  const _DriversPanel({required this.service});

  @override
  State<_DriversPanel> createState() => _DriversPanelState();
}

class _DriversPanelState extends State<_DriversPanel> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 24, 16),
      child: Container(
        decoration: _cardDecoration(
          radius: 28,
        ).copyWith(color: NavigoColors.surfaceWhite),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: texts.t('drivers'),
              subtitle: texts.t('driversSubtitle'),
              searchHint: texts.t('searchDrivers'),
              onSearchChanged: (value) {
                setState(() => _searchQuery = value.trim().toLowerCase());
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<AdminDriverItem>>(
                stream: widget.service.adminDriversStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        '${texts.t('errorLoadingDrivers')}: ${snapshot.error}',
                      ),
                    );
                  }

                  final drivers = (snapshot.data ?? []).where((driver) {
                    if (_searchQuery.isEmpty) return true;

                    return driver.fullName.toLowerCase().contains(
                          _searchQuery,
                        ) ||
                        driver.phone.toLowerCase().contains(_searchQuery) ||
                        driver.vehicleType.toLowerCase().contains(
                          _searchQuery,
                        ) ||
                        driver.routeLabel.toLowerCase().contains(
                          _searchQuery,
                        ) ||
                        driver.plateNumber.toLowerCase().contains(_searchQuery);
                  }).toList();

                  if (drivers.isEmpty) {
                    return Center(
                      child: Text(
                        texts.t('noDriversFound'),
                        style: NavigoTextStyles.bodyMedium,
                      ),
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth - 48,
                            ),
                            child: DataTable(
                              columnSpacing: 36,
                              headingRowHeight: 58,
                              dataRowMinHeight: 64,
                              dataRowMaxHeight: 76,
                              headingTextStyle: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              dataTextStyle: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              headingRowColor: const WidgetStatePropertyAll(
                                NavigoColors.backgroundAlt,
                              ),
                              columns: [
                                DataColumn(label: Text(texts.t('name'))),
                                DataColumn(label: Text(texts.t('phone'))),
                                DataColumn(label: Text(texts.t('status'))),
                                DataColumn(label: Text(texts.t('approval'))),
                                DataColumn(label: Text(texts.t('vehicle'))),
                                DataColumn(label: Text(texts.t('route'))),
                                DataColumn(label: Text(texts.t('details'))),
                              ],
                              rows: drivers.map((driver) {
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        driver.fullName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    DataCell(_LtrText(_dash(driver.phone))),
                                    DataCell(
                                      _Chip(
                                        label: driver.isOnline
                                            ? texts.t('online')
                                            : _formatStatus(driver.status),
                                        color: driver.isOnline
                                            ? NavigoColors.accentGreen
                                            : NavigoColors.textGray,
                                      ),
                                    ),
                                    DataCell(
                                      _Chip(
                                        label: driver.isApproved
                                            ? texts.t('approved')
                                            : _formatStatus(
                                                driver.approvalStatus,
                                              ),
                                        color: driver.isApproved
                                            ? NavigoColors.accentGreen
                                            : NavigoColors.primaryOrange,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        _localizedVehicleType(
                                          context,
                                          driver.vehicleType,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        _localizedRouteName(
                                          context,
                                          label: driver.routeLabel,
                                          fallback: '',
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      TextButton.icon(
                                        onPressed: () =>
                                            _showDriverDetails(context, driver),
                                        icon: const Icon(
                                          Icons.open_in_new_rounded,
                                          size: 16,
                                        ),
                                        label: Text(texts.t('open')),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDriverDetails(BuildContext context, AdminDriverItem driver) {
    final texts = context.texts;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 56,
            vertical: 40,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.purple.withValues(
                            alpha: 0.12,
                          ),
                          child: const Icon(
                            Icons.local_taxi_rounded,
                            color: Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            driver.fullName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: texts.t('close'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _DetailSection(
                      title: texts.t('accountInformation'),
                      children: [
                        _DetailRow(
                          label: texts.t('email'),
                          value: driver.email,
                        ),
                        _DetailRow(
                          label: texts.t('phone'),
                          value: driver.phone,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: texts.t('driverStatus'),
                      children: [
                        _DetailRow(
                          label: texts.t('online'),
                          value: driver.isOnline
                              ? texts.t('yes')
                              : texts.t('no'),
                        ),
                        _DetailRow(
                          label: texts.t('status'),
                          value: _formatStatus(driver.status),
                        ),
                        _DetailRow(
                          label: texts.t('approved'),
                          value: driver.isApproved
                              ? texts.t('yes')
                              : texts.t('no'),
                        ),
                        _DetailRow(
                          label: texts.t('approvalStatus'),
                          value: _formatStatus(driver.approvalStatus),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: texts.t('routeAndVehicle'),
                      children: [
                        _DetailRow(
                          label: texts.t('route'),
                          value: _localizedRouteName(
                            context,
                            label: driver.routeLabel,
                            fallback: '',
                          ),
                        ),
                        _DetailRow(
                          label: texts.t('vehicleType'),
                          value: _localizedVehicleType(
                            context,
                            driver.vehicleType,
                          ),
                        ),
                        _DetailRow(
                          label: texts.t('plateNumber'),
                          value: driver.plateNumber,
                        ),
                        _DetailRow(
                          label: texts.t('licenseNumber'),
                          value: driver.licenseNumber,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: texts.t('dates'),
                      children: [
                        _DetailRow(
                          label: texts.t('createdAt'),
                          value: _formatDate(driver.createdAt),
                        ),
                        _DetailRow(
                          label: texts.t('updatedAt'),
                          value: _formatDate(driver.updatedAt),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: NavigoColors.primaryOrange,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(texts.t('close')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoutesPanel extends StatefulWidget {
  final AdminDashboardService service;

  const _RoutesPanel({required this.service});

  @override
  State<_RoutesPanel> createState() => _RoutesPanelState();
}

class _RoutesPanelState extends State<_RoutesPanel> {
  String _searchQuery = '';

  Future<void> _showCreateRouteDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => _CreateRouteDialog(service: widget.service),
    );

    if (!mounted || created != true) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.texts.t('routeCreated'))));
  }

  Future<void> _showEditRouteDialog(AdminRouteItem route) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _CreateRouteDialog(service: widget.service, route: route),
    );

    if (!mounted || updated != true) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.texts.t('routeUpdated'))));
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 24, 16),
      child: Container(
        decoration: _cardDecoration(
          radius: 28,
        ).copyWith(color: NavigoColors.surfaceWhite),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(34),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          texts.t('routes'),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          texts.t('routesSubtitle'),
                          style: NavigoTextStyles.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      onChanged: (value) {
                        setState(
                          () => _searchQuery = value.trim().toLowerCase(),
                        );
                      },
                      decoration: NavigoDecorations.kInputDecoration.copyWith(
                        hintText: texts.t('searchRoutes'),
                        prefixIcon: const Icon(Icons.search),
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  FilledButton.icon(
                    onPressed: _showCreateRouteDialog,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(texts.t('createRoute')),
                    style: FilledButton.styleFrom(
                      backgroundColor: NavigoColors.primaryOrange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<AdminRouteItem>>(
                stream: widget.service.adminRoutesStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        '${texts.t('errorLoadingRoutes')}: ${snapshot.error}',
                      ),
                    );
                  }

                  final routes = (snapshot.data ?? []).where((route) {
                    if (_searchQuery.isEmpty) return true;

                    return route.routeId.toLowerCase().contains(_searchQuery) ||
                        route.startPoint.toLowerCase().contains(_searchQuery) ||
                        route.endPoint.toLowerCase().contains(_searchQuery) ||
                        route.vehicleTypes
                            .join(', ')
                            .toLowerCase()
                            .contains(_searchQuery);
                  }).toList();

                  if (routes.isEmpty) {
                    return Center(
                      child: Text(
                        texts.t('noRoutesFound'),
                        style: NavigoTextStyles.bodyMedium,
                      ),
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth - 48,
                            ),
                            child: DataTable(
                              columnSpacing: 36,
                              headingRowHeight: 58,
                              dataRowMinHeight: 64,
                              dataRowMaxHeight: 76,
                              headingTextStyle: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              dataTextStyle: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              headingRowColor: const WidgetStatePropertyAll(
                                NavigoColors.backgroundAlt,
                              ),
                              columns: [
                                DataColumn(label: Text(texts.t('start'))),
                                DataColumn(label: Text(texts.t('end'))),
                                DataColumn(label: Text(texts.t('price'))),
                                DataColumn(label: Text(texts.t('vehicles'))),
                                DataColumn(label: Text(texts.t('slots'))),
                                DataColumn(label: Text(texts.t('driverQueue'))),
                                DataColumn(label: Text(texts.t('updated'))),
                                DataColumn(label: Text(texts.t('actions'))),
                              ],
                              rows: routes.map((route) {
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        _localizedPlaceName(
                                          context,
                                          route.startPoint,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        _localizedPlaceName(
                                          context,
                                          route.endPoint,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      _LtrText(route.price.toStringAsFixed(2)),
                                    ),
                                    DataCell(
                                      Text(
                                        route.vehicleTypes.isEmpty
                                            ? '-'
                                            : route.vehicleTypes
                                                  .map(
                                                    (type) =>
                                                        _localizedVehicleType(
                                                          context,
                                                          type,
                                                        ),
                                                  )
                                                  .join(', '),
                                      ),
                                    ),
                                    DataCell(
                                      _LtrText(
                                        route.scheduleSlotCount.toString(),
                                      ),
                                    ),
                                    DataCell(
                                      _LtrText(
                                        route.driverQueueCount.toString(),
                                      ),
                                    ),
                                    DataCell(
                                      _LtrText(_formatDate(route.updatedAt)),
                                    ),
                                    DataCell(
                                      IconButton(
                                        onPressed: () =>
                                            _showEditRouteDialog(route),
                                        icon: const Icon(Icons.edit_rounded),
                                        tooltip: texts.t('editRoute'),
                                        color: NavigoColors.accentBlue,
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateRouteDialog extends StatefulWidget {
  final AdminDashboardService service;
  final AdminRouteItem? route;

  const _CreateRouteDialog({required this.service, this.route});

  @override
  State<_CreateRouteDialog> createState() => _CreateRouteDialogState();
}

class _CreateRouteDialogState extends State<_CreateRouteDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _priceController;
  late final Set<String> _selectedVehicleTypes;
  LatLng? _startLocation;
  LatLng? _endLocation;
  bool _isSelectingStartLocation = true;
  bool _isSaving = false;

  bool get _isEditing => widget.route != null;

  @override
  void initState() {
    super.initState();
    final route = widget.route;
    _startController = TextEditingController(text: route?.startPoint ?? '');
    _endController = TextEditingController(text: route?.endPoint ?? '');
    _priceController = TextEditingController(
      text: route == null ? '' : route.price.toString(),
    );
    _selectedVehicleTypes = route == null
        ? {'bus 14', 'bus 45', 'microbus'}
        : route.vehicleTypes.toSet();
    if (route?.startLatitude != null && route?.startLongitude != null) {
      _startLocation = LatLng(route!.startLatitude!, route.startLongitude!);
    }
    if (route?.endLatitude != null && route?.endLongitude != null) {
      _endLocation = LatLng(route!.endLatitude!, route.endLongitude!);
    }
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _saveRoute() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final vehicleTypes = _selectedVehicleTypes.toList();

      if (_isEditing) {
        await widget.service.updateRoute(
          documentId: widget.route!.documentId,
          startPoint: _startController.text,
          endPoint: _endController.text,
          startLatitude: _startLocation!.latitude,
          startLongitude: _startLocation!.longitude,
          endLatitude: _endLocation!.latitude,
          endLongitude: _endLocation!.longitude,
          price: double.parse(_priceController.text.trim()),
          vehicleTypes: vehicleTypes,
        );
      } else {
        await widget.service.createRoute(
          startPoint: _startController.text,
          endPoint: _endController.text,
          startLatitude: _startLocation!.latitude,
          startLongitude: _startLocation!.longitude,
          endLatitude: _endLocation!.latitude,
          endLongitude: _endLocation!.longitude,
          price: double.parse(_priceController.text.trim()),
          vehicleTypes: vehicleTypes,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.texts.t(_isEditing ? 'couldNotUpdateRoute' : 'couldNotCreateRoute')}: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _setVehicleTypeSelected(String type, bool selected) {
    setState(() {
      if (selected) {
        _selectedVehicleTypes.add(type);
      } else {
        _selectedVehicleTypes.remove(type);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalInset = constraints.maxWidth < 720 ? 12.0 : 56.0;
        final verticalInset = constraints.maxHeight < 720 ? 12.0 : 40.0;
        final dialogWidth = constraints.maxWidth - (horizontalInset * 2);
        final dialogHeight = constraints.maxHeight - (verticalInset * 2);
        final compact = dialogWidth < 680 || dialogHeight < 720;

        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: horizontalInset,
            vertical: verticalInset,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 860, maxHeight: dialogHeight),
            child: Padding(
              padding: EdgeInsets.all(compact ? 18 : 28),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              texts.t(_isEditing ? 'editRoute' : 'createRoute'),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _isSaving
                                ? null
                                : () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: texts.t('close'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: compact
                            ? [
                                Expanded(
                                  child: Column(
                                    children: [
                                      _RouteLocationField(
                                        controller: _startController,
                                        labelText: texts.t('startPoint'),
                                        icon: Icons.trip_origin_rounded,
                                        selectedLocation: _startLocation,
                                        validationMessage: texts.t(
                                          'startPointRequired',
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      _RouteLocationField(
                                        controller: _endController,
                                        labelText: texts.t('endPoint'),
                                        icon: Icons.location_on_rounded,
                                        selectedLocation: _endLocation,
                                        validationMessage: texts.t(
                                          'endPointRequired',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ]
                            : [
                                Expanded(
                                  child: _RouteLocationField(
                                    controller: _startController,
                                    labelText: texts.t('startPoint'),
                                    icon: Icons.trip_origin_rounded,
                                    selectedLocation: _startLocation,
                                    validationMessage: texts.t(
                                      'startPointRequired',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _RouteLocationField(
                                    controller: _endController,
                                    labelText: texts.t('endPoint'),
                                    icon: Icons.location_on_rounded,
                                    selectedLocation: _endLocation,
                                    validationMessage: texts.t(
                                      'endPointRequired',
                                    ),
                                  ),
                                ),
                              ],
                      ),
                      const SizedBox(height: 14),
                      _RouteMapSelector(
                        height: compact ? 220 : 330,
                        startLocation: _startLocation,
                        endLocation: _endLocation,
                        isSelectingStart: _isSelectingStartLocation,
                        compact: compact,
                        onSelectingChanged: (isSelectingStart) {
                          setState(
                            () => _isSelectingStartLocation = isSelectingStart,
                          );
                        },
                        onLocationSelected: (location) {
                          setState(() {
                            if (_isSelectingStartLocation) {
                              _startLocation = location;
                              _isSelectingStartLocation = false;
                            } else {
                              _endLocation = location;
                            }
                          });
                        },
                      ),
                      FormField<bool>(
                        validator: (_) {
                          if (_startLocation == null && _endLocation == null) {
                            return texts.t('pickStartEndLocations');
                          }
                          if (_startLocation == null) {
                            return texts.t('pickStartLocation');
                          }
                          if (_endLocation == null) {
                            return texts.t('pickEndLocation');
                          }
                          return null;
                        },
                        builder: (field) {
                          if (!field.hasError) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              field.errorText!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: compact
                            ? [
                                Expanded(
                                  child: Column(
                                    children: [
                                      _RoutePriceField(
                                        controller: _priceController,
                                      ),
                                      const SizedBox(height: 14),
                                      _RouteVehicleTypesField(
                                        selectedVehicleTypes:
                                            _selectedVehicleTypes,
                                        onChanged: _setVehicleTypeSelected,
                                      ),
                                    ],
                                  ),
                                ),
                              ]
                            : [
                                Expanded(
                                  child: _RoutePriceField(
                                    controller: _priceController,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _RouteVehicleTypesField(
                                    selectedVehicleTypes: _selectedVehicleTypes,
                                    onChanged: _setVehicleTypeSelected,
                                  ),
                                ),
                              ],
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _saveRoute,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _isEditing
                                      ? Icons.save_rounded
                                      : Icons.add_rounded,
                                ),
                          label: Text(
                            _isSaving
                                ? texts.t(_isEditing ? 'saving' : 'creating')
                                : texts.t(
                                    _isEditing ? 'saveChanges' : 'createRoute',
                                  ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: NavigoColors.primaryOrange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RouteLocationField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final IconData icon;
  final LatLng? selectedLocation;
  final String validationMessage;

  const _RouteLocationField({
    required this.controller,
    required this.labelText,
    required this.icon,
    required this.selectedLocation,
    required this.validationMessage,
  });

  @override
  Widget build(BuildContext context) {
    final location = selectedLocation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          decoration: NavigoDecorations.kInputDecoration.copyWith(
            labelText: labelText,
            prefixIcon: Icon(icon),
            fillColor: Colors.white,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return validationMessage;
            }
            return null;
          },
        ),
        if (location != null) ...[
          const SizedBox(height: 6),
          Text(
            '${context.texts.t('selected')}: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            style: NavigoTextStyles.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _RoutePriceField extends StatelessWidget {
  final TextEditingController controller;

  const _RoutePriceField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      decoration: NavigoDecorations.kInputDecoration.copyWith(
        labelText: texts.t('price'),
        prefixIcon: const Icon(Icons.payments_rounded),
        fillColor: Colors.white,
      ),
      validator: (value) {
        final price = double.tryParse(value?.trim() ?? '');
        if (price == null || price < 0) {
          return texts.t('enterValidPrice');
        }
        return null;
      },
    );
  }
}

class _RouteVehicleTypesField extends StatelessWidget {
  static const Map<String, String> _options = {
    'bus 14': 'Bus 14',
    'bus 45': 'Bus 45',
    'microbus': 'Microbus',
  };

  final Set<String> selectedVehicleTypes;
  final void Function(String type, bool selected) onChanged;

  const _RouteVehicleTypesField({
    required this.selectedVehicleTypes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return FormField<Set<String>>(
      initialValue: selectedVehicleTypes,
      validator: (value) {
        if (selectedVehicleTypes.isEmpty) {
          return texts.t('addVehicleType');
        }
        return null;
      },
      builder: (field) {
        return InputDecorator(
          decoration: NavigoDecorations.kInputDecoration.copyWith(
            labelText: texts.t('vehicleTypes'),
            prefixIcon: const Icon(Icons.directions_bus_rounded),
            fillColor: Colors.white,
            errorText: field.errorText,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _options.entries.map((entry) {
              return FilterChip(
                label: Text(entry.value),
                selected: selectedVehicleTypes.contains(entry.key),
                onSelected: (selected) {
                  onChanged(entry.key, selected);
                  field.didChange(selectedVehicleTypes);
                },
                selectedColor: NavigoColors.primaryOrange.withValues(
                  alpha: 0.16,
                ),
                checkmarkColor: NavigoColors.primaryOrange,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _RouteMapSelector extends StatefulWidget {
  final LatLng? startLocation;
  final LatLng? endLocation;
  final double height;
  final bool compact;
  final bool isSelectingStart;
  final ValueChanged<bool> onSelectingChanged;
  final ValueChanged<LatLng> onLocationSelected;

  const _RouteMapSelector({
    required this.startLocation,
    required this.endLocation,
    required this.height,
    required this.compact,
    required this.isSelectingStart,
    required this.onSelectingChanged,
    required this.onLocationSelected,
  });

  @override
  State<_RouteMapSelector> createState() => _RouteMapSelectorState();
}

class _RouteMapSelectorState extends State<_RouteMapSelector> {
  static const LatLng _defaultCenter = LatLng(31.9522, 35.2332);
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  LatLng? _searchedLocation;
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    _mapController.move(camera.center, camera.zoom + delta);
  }

  Future<void> _searchLocation() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _isSearching) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSearching = true);

    try {
      final location = await _findLocation(query);
      if (!mounted) return;

      if (location == null) {
        _showSearchError(context.texts.t('locationNotFound'));
        return;
      }

      setState(() => _searchedLocation = location);
      widget.onLocationSelected(location);
      _mapController.move(location, 15);
    } catch (_) {
      if (!mounted) return;
      _showSearchError(context.texts.t('locationSearchFailed'));
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _showSearchError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<LatLng?> _findLocation(String query) async {
    final candidates = <String>[
      query,
      '$query, Palestine',
      '$query, West Bank',
    ];

    for (final candidate in candidates) {
      try {
        final locations = await locationFromAddress(candidate);
        if (locations.isNotEmpty) {
          final first = locations.first;
          return LatLng(first.latitude, first.longitude);
        }
      } on NoResultFoundException {
        // Try the next candidate, then the HTTP fallback.
      } catch (_) {
        // Platform geocoders can fail on desktop/web; use the HTTP fallback.
        break;
      }
    }

    return _findLocationWithNominatim(query);
  }

  Future<LatLng?> _findLocationWithNominatim(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'jsonv2',
      'limit': '1',
      'addressdetails': '1',
      'accept-language': Localizations.localeOf(context).languageCode,
      // Bias results toward Palestine while still allowing broader searches.
      'viewbox': '34.15,32.65,35.75,31.15',
      'bounded': '0',
    });

    final response = await http.get(
      uri,
      headers: const {'User-Agent': 'NavigoAdmin/1.0 (route-search)'},
    );

    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) return null;

    final first = decoded.first;
    if (first is! Map) return null;

    final lat = double.tryParse(first['lat']?.toString() ?? '');
    final lon = double.tryParse(first['lon']?.toString() ?? '');
    if (lat == null || lon == null) return null;

    return LatLng(lat, lon);
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    final start = widget.startLocation;
    final end = widget.endLocation;
    final markers = <Marker>[
      if (start != null)
        Marker(
          point: start,
          width: 52,
          height: 52,
          child: const Icon(
            Icons.trip_origin_rounded,
            color: NavigoColors.accentGreen,
            size: 38,
          ),
        ),
      if (end != null)
        Marker(
          point: end,
          width: 52,
          height: 52,
          child: const Icon(
            Icons.location_pin,
            color: NavigoColors.primaryOrange,
            size: 44,
          ),
        ),
      if (_searchedLocation != null)
        Marker(
          point: _searchedLocation!,
          width: 48,
          height: 48,
          child: const Icon(
            Icons.search_rounded,
            color: NavigoColors.accentBlue,
            size: 34,
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(texts.t('routeLocations'), style: NavigoTextStyles.titleSmall),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.trip_origin_rounded),
                  label: Text(texts.t('start')),
                ),
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.location_on_rounded),
                  label: Text(texts.t('end')),
                ),
              ],
              selected: {widget.isSelectingStart},
              onSelectionChanged: (selection) {
                widget.onSelectingChanged(selection.first);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          widget.isSelectingStart
              ? texts.t('setStartOnMap')
              : texts.t('setEndOnMap'),
          style: NavigoTextStyles.bodySmall,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: widget.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: start ?? end ?? _defaultCenter,
                    initialZoom: 11,
                    minZoom: 4,
                    maxZoom: 18,
                    onTap: (_, location) {
                      widget.onLocationSelected(location);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.admin_panel',
                    ),
                    MarkerLayer(markers: markers),
                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 78,
                  right: 12,
                  child: Column(
                    children: [
                      _MapZoomButton(
                        icon: Icons.add_rounded,
                        tooltip: texts.t('zoomIn'),
                        onPressed: () => _zoomBy(1),
                      ),
                      const SizedBox(height: 8),
                      _MapZoomButton(
                        icon: Icons.remove_rounded,
                        tooltip: texts.t('zoomOut'),
                        onPressed: () => _zoomBy(-1),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: _MapSearchBar(
                    controller: _searchController,
                    isSearching: _isSearching,
                    onSearch: _searchLocation,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            SizedBox(
              width: widget.compact ? double.infinity : 390,
              child: _MapCoordinateLabel(
                label: texts.t('start'),
                location: start,
                color: NavigoColors.accentGreen,
              ),
            ),
            SizedBox(
              width: widget.compact ? double.infinity : 390,
              child: _MapCoordinateLabel(
                label: texts.t('end'),
                location: end,
                color: NavigoColors.primaryOrange,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MapZoomButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _MapZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        tooltip: tooltip,
        color: NavigoColors.textDark,
      ),
    );
  }
}

class _MapSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSearching;
  final VoidCallback onSearch;

  const _MapSearchBar({
    required this.controller,
    required this.isSearching,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: TextField(
        controller: controller,
        enabled: !isSearching,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onSearch(),
        decoration: NavigoDecorations.kInputDecoration.copyWith(
          hintText: texts.t('searchLocationHint'),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: isSearching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: onSearch,
                  icon: const Icon(Icons.my_location_rounded),
                  tooltip: texts.t('searchLocation'),
                ),
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: NavigoColors.primaryOrange),
          ),
        ),
      ),
    );
  }
}

class _MapCoordinateLabel extends StatelessWidget {
  final String label;
  final LatLng? location;
  final Color color;

  const _MapCoordinateLabel({
    required this.label,
    required this.location,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final value = location == null
        ? 'Not selected'
        : '${location!.latitude.toStringAsFixed(6)}, ${location!.longitude.toStringAsFixed(6)}';

    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$label: $value', style: NavigoTextStyles.bodySmall),
        ),
      ],
    );
  }
}

class _RouteManagersPanel extends StatefulWidget {
  final AdminDashboardService service;

  const _RouteManagersPanel({required this.service});

  @override
  State<_RouteManagersPanel> createState() => _RouteManagersPanelState();
}

class _RouteManagersPanelState extends State<_RouteManagersPanel> {
  String _searchQuery = '';

  Future<void> _showCreateRouteManagerDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => _CreateRouteManagerDialog(service: widget.service),
    );

    if (!mounted || created != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.texts.t('routeManagerCreated'))),
    );
  }

  Future<void> _showEditRouteManagerDialog(
    AdminRouteManagerItem manager,
  ) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _EditRouteManagerDialog(service: widget.service, manager: manager),
    );

    if (!mounted || updated != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.texts.t('routeManagerUpdated'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 24, 16),
      child: Container(
        decoration: _cardDecoration(
          radius: 28,
        ).copyWith(color: NavigoColors.surfaceWhite),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: texts.t('routeManagers'),
              subtitle: texts.t('routeManagersSubtitle'),
              searchHint: texts.t('searchRouteManagers'),
              onSearchChanged: (value) {
                setState(() => _searchQuery = value.trim().toLowerCase());
              },
              trailing: FilledButton.icon(
                onPressed: _showCreateRouteManagerDialog,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(texts.t('createRouteManager')),
                style: FilledButton.styleFrom(
                  backgroundColor: NavigoColors.primaryOrange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<AdminRouteManagerItem>>(
                stream: widget.service.adminRouteManagersStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        '${texts.t('errorLoadingRouteManagers')}: ${snapshot.error}',
                      ),
                    );
                  }

                  final managers = (snapshot.data ?? []).where((manager) {
                    if (_searchQuery.isEmpty) return true;

                    return manager.fullName.toLowerCase().contains(
                          _searchQuery,
                        ) ||
                        manager.email.toLowerCase().contains(_searchQuery) ||
                        manager.phone.toLowerCase().contains(_searchQuery) ||
                        manager.routeLabel.toLowerCase().contains(
                          _searchQuery,
                        ) ||
                        manager.routeId.toLowerCase().contains(_searchQuery);
                  }).toList();

                  if (managers.isEmpty) {
                    return Center(
                      child: Text(
                        texts.t('noRouteManagersFound'),
                        style: NavigoTextStyles.bodyMedium,
                      ),
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth - 48,
                            ),
                            child: DataTable(
                              columnSpacing: 36,
                              headingRowHeight: 58,
                              dataRowMinHeight: 64,
                              dataRowMaxHeight: 76,
                              headingTextStyle: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              dataTextStyle: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              headingRowColor: const WidgetStatePropertyAll(
                                NavigoColors.backgroundAlt,
                              ),
                              columns: [
                                DataColumn(label: Text(texts.t('name'))),
                                DataColumn(label: Text(texts.t('email'))),
                                DataColumn(label: Text(texts.t('phone'))),
                                DataColumn(label: Text(texts.t('route'))),
                                DataColumn(label: Text(texts.t('verified'))),
                                DataColumn(label: Text(texts.t('online'))),
                                DataColumn(label: Text(texts.t('actions'))),
                              ],
                              rows: managers.map((manager) {
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        manager.fullName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(_dash(manager.email))),
                                    DataCell(_LtrText(_dash(manager.phone))),
                                    DataCell(
                                      Text(
                                        _localizedRouteName(
                                          context,
                                          label: manager.routeLabel,
                                          fallback: '',
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      _Chip(
                                        label: manager.isVerified
                                            ? texts.t('yes')
                                            : texts.t('no'),
                                        color: manager.isVerified
                                            ? NavigoColors.accentGreen
                                            : NavigoColors.primaryOrange,
                                      ),
                                    ),
                                    DataCell(
                                      _Chip(
                                        label: manager.isOnline
                                            ? texts.t('online')
                                            : texts.t('offline'),
                                        color: manager.isOnline
                                            ? NavigoColors.accentGreen
                                            : NavigoColors.textGray,
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            onPressed: () =>
                                                _showEditRouteManagerDialog(
                                                  manager,
                                                ),
                                            icon: const Icon(
                                              Icons.edit_rounded,
                                              size: 20,
                                            ),
                                            tooltip: texts.t('edit'),
                                          ),
                                          TextButton.icon(
                                            onPressed: () =>
                                                _showRouteManagerDetails(
                                                  context,
                                                  manager,
                                                ),
                                            icon: const Icon(
                                              Icons.open_in_new_rounded,
                                              size: 16,
                                            ),
                                            label: Text(texts.t('open')),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRouteManagerDetails(
    BuildContext context,
    AdminRouteManagerItem manager,
  ) {
    final texts = context.texts;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 56,
            vertical: 40,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: NavigoColors.primaryOrange
                              .withValues(alpha: 0.12),
                          child: const Icon(
                            Icons.manage_accounts_rounded,
                            color: NavigoColors.primaryOrange,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            manager.fullName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: texts.t('close'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _DetailSection(
                      title: texts.t('accountInformation'),
                      children: [
                        _DetailRow(
                          label: texts.t('email'),
                          value: manager.email,
                        ),
                        _DetailRow(
                          label: texts.t('phone'),
                          value: manager.phone,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: texts.t('routeAssignment'),
                      children: [
                        _DetailRow(
                          label: texts.t('route'),
                          value: _localizedRouteName(
                            context,
                            label: manager.routeLabel,
                            fallback: '',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: texts.t('status'),
                      children: [
                        _DetailRow(
                          label: texts.t('verified'),
                          value: manager.isVerified
                              ? texts.t('yes')
                              : texts.t('no'),
                        ),
                        _DetailRow(
                          label: texts.t('online'),
                          value: manager.isOnline
                              ? texts.t('yes')
                              : texts.t('no'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: texts.t('dates'),
                      children: [
                        _DetailRow(
                          label: texts.t('createdAt'),
                          value: _formatDate(manager.createdAt),
                        ),
                        _DetailRow(
                          label: texts.t('updatedAt'),
                          value: _formatDate(manager.updatedAt),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: NavigoColors.primaryOrange,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(texts.t('close')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TripsPanel extends StatefulWidget {
  final AdminDashboardService service;

  const _TripsPanel({required this.service});

  @override
  State<_TripsPanel> createState() => _TripsPanelState();
}

class _TripsPanelState extends State<_TripsPanel> {
  String _selectedRoute = 'All Routes';

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    final allRoutesLabel = texts.t('allRoutes');

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 24, 16),
      child: Container(
        decoration: _cardDecoration(
          radius: 28,
        ).copyWith(color: NavigoColors.surfaceWhite),
        child: StreamBuilder<List<AdminTripItem>>(
          stream: widget.service.adminTripsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  '${texts.t('errorLoadingTrips')}: ${snapshot.error}',
                ),
              );
            }

            final trips = snapshot.data ?? [];
            final routeNames =
                <String>{
                  'All Routes',
                  ...trips.map((trip) => trip.routeLabel),
                }.toList()..sort((a, b) {
                  if (a == 'All Routes') return -1;
                  if (b == 'All Routes') return 1;
                  return a.compareTo(b);
                });

            if (!routeNames.contains(_selectedRoute)) {
              _selectedRoute = 'All Routes';
            }

            final visibleTrips = _selectedRoute == 'All Routes'
                ? trips
                : trips
                      .where((trip) => trip.routeLabel == _selectedRoute)
                      .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(34),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              texts.t('trips'),
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              texts.t('tripsSubtitle'),
                              style: NavigoTextStyles.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 320,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedRoute,
                          decoration: NavigoDecorations.kInputDecoration
                              .copyWith(
                                labelText: texts.t('filterByRoute'),
                                prefixIcon: const Icon(Icons.route_rounded),
                                fillColor: Colors.white,
                              ),
                          items: routeNames
                              .map(
                                (route) => DropdownMenuItem(
                                  value: route,
                                  child: Text(
                                    route == 'All Routes'
                                        ? allRoutesLabel
                                        : _localizedRouteName(
                                            context,
                                            label: route,
                                          ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _selectedRoute = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(34, 18, 34, 0),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    children: [
                      _SummaryPill(
                        icon: Icons.directions_bus_rounded,
                        label: '${visibleTrips.length} ${texts.t('trips')}',
                        color: NavigoColors.primaryOrange,
                      ),
                      _SummaryPill(
                        icon: Icons.route_rounded,
                        label:
                            '${routeNames.where((route) => route != 'All Routes').length} ${texts.t('routes')}',
                        color: NavigoColors.accentBlue,
                      ),
                      _SummaryPill(
                        icon: Icons.people_alt_rounded,
                        label:
                            '${visibleTrips.fold<int>(0, (sum, trip) => sum + trip.passengerCount)} ${texts.t('passengers')}',
                        color: NavigoColors.accentGreen,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visibleTrips.isEmpty
                      ? Center(
                          child: Text(
                            texts.t('noTripsFoundForRoute'),
                            style: NavigoTextStyles.bodyMedium,
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(34),
                          itemCount: visibleTrips.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            return _TripCard(trip: visibleTrips[index]);
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final AdminTripItem trip;

  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    final seatsLeft = trip.capacity - trip.passengerCount;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBox(
                icon: Icons.directions_bus_rounded,
                color: NavigoColors.primaryOrange,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizedRouteName(context, label: trip.routeLabel),
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Slot ${trip.slotId}',
                      style: NavigoTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              _Chip(
                label: _localizedTripStatus(context, trip.status),
                color: _tripStatusColor(trip.status),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 18,
            runSpacing: 14,
            children: [
              _TripInfo(
                icon: Icons.schedule_rounded,
                label: texts.t('departure'),
                value: _formatDate(trip.departureAt),
              ),
              _TripInfo(
                icon: Icons.flag_rounded,
                label: texts.t('arrival'),
                value: _formatDate(trip.arrivalAt),
              ),
              _TripInfo(
                icon: Icons.airport_shuttle_rounded,
                label: texts.t('vehicle'),
                value: _localizedVehicleType(context, trip.vehicleType),
              ),
              _TripInfo(
                icon: Icons.event_seat_rounded,
                label: texts.t('seats'),
                value:
                    '${trip.passengerCount}/${trip.capacity} ${texts.t('booked')}, ${seatsLeft < 0 ? 0 : seatsLeft} ${texts.t('left')}',
              ),
              _TripInfo(
                icon: Icons.payments_rounded,
                label: texts.t('price'),
                value: trip.price == null
                    ? '-'
                    : '${trip.price!.toStringAsFixed(2)} NIS',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TripInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _TripInfo({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: NavigoColors.textGray),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: NavigoTextStyles.bodySmall),
                const SizedBox(height: 3),
                Text(
                  value,
                  textDirection: _looksNumeric(value)
                      ? TextDirection.ltr
                      : null,
                  textAlign: _looksNumeric(value)
                      ? TextAlign.left
                      : TextAlign.start,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SummaryPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.black),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PassengersPanel extends StatefulWidget {
  final AdminDashboardService service;

  const _PassengersPanel({required this.service});

  @override
  State<_PassengersPanel> createState() => _PassengersPanelState();
}

class _PassengersPanelState extends State<_PassengersPanel> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 24, 16),
      child: Container(
        decoration: _cardDecoration(
          radius: 28,
        ).copyWith(color: NavigoColors.surfaceWhite),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: texts.t('passengers'),
              subtitle: texts.t('passengersSubtitle'),
              searchHint: texts.t('searchPassengers'),
              onSearchChanged: (value) {
                setState(() => _searchQuery = value.trim().toLowerCase());
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<AdminPassengerItem>>(
                stream: widget.service.adminPassengersStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        '${texts.t('errorLoadingPassengers')}: ${snapshot.error}',
                      ),
                    );
                  }

                  final passengers = (snapshot.data ?? []).where((passenger) {
                    if (_searchQuery.isEmpty) return true;

                    return passenger.fullName.toLowerCase().contains(
                          _searchQuery,
                        ) ||
                        passenger.phone.toLowerCase().contains(_searchQuery) ||
                        passenger.pickupLocationDescription
                            .toLowerCase()
                            .contains(_searchQuery);
                  }).toList();

                  if (passengers.isEmpty) {
                    return Center(
                      child: Text(
                        texts.t('noPassengersFound'),
                        style: NavigoTextStyles.bodyMedium,
                      ),
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth - 48,
                            ),
                            child: DataTable(
                              columnSpacing: 36,
                              headingRowHeight: 58,
                              dataRowMinHeight: 64,
                              dataRowMaxHeight: 76,
                              headingTextStyle: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              dataTextStyle: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              headingRowColor: const WidgetStatePropertyAll(
                                NavigoColors.backgroundAlt,
                              ),
                              columns: [
                                DataColumn(label: Text(texts.t('name'))),
                                DataColumn(label: Text(texts.t('phone'))),
                                DataColumn(label: Text(texts.t('verified'))),
                                DataColumn(label: Text(texts.t('online'))),
                                DataColumn(label: Text(texts.t('pickup'))),
                                DataColumn(
                                  label: Text(texts.t('lastLocation')),
                                ),
                                DataColumn(label: Text(texts.t('details'))),
                              ],
                              rows: passengers.map((passenger) {
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        passenger.fullName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    DataCell(_LtrText(_dash(passenger.phone))),
                                    DataCell(
                                      _Chip(
                                        label: passenger.isVerified
                                            ? texts.t('yes')
                                            : texts.t('no'),
                                        color: passenger.isVerified
                                            ? NavigoColors.accentGreen
                                            : NavigoColors.primaryOrange,
                                      ),
                                    ),
                                    DataCell(
                                      _Chip(
                                        label: passenger.isOnline
                                            ? texts.t('online')
                                            : texts.t('offline'),
                                        color: passenger.isOnline
                                            ? NavigoColors.accentGreen
                                            : NavigoColors.textGray,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        _dash(
                                          passenger.pickupLocationDescription,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        _formatDate(
                                          passenger.lastLocationUpdate,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      TextButton.icon(
                                        onPressed: () => _showPassengerDetails(
                                          context,
                                          passenger,
                                        ),
                                        icon: const Icon(
                                          Icons.open_in_new_rounded,
                                          size: 16,
                                        ),
                                        label: Text(texts.t('open')),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPassengerDetails(
    BuildContext context,
    AdminPassengerItem passenger,
  ) {
    final texts = context.texts;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 56,
            vertical: 40,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: NavigoColors.accentBlue.withValues(
                            alpha: 0.12,
                          ),
                          child: const Icon(
                            Icons.people_alt_rounded,
                            color: NavigoColors.accentBlue,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            passenger.fullName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: texts.t('close'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _DetailSection(
                      title: texts.t('accountInformation'),
                      children: [
                        _DetailRow(
                          label: texts.t('email'),
                          value: passenger.email,
                        ),
                        _DetailRow(
                          label: texts.t('phone'),
                          value: passenger.phone,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: texts.t('status'),
                      children: [
                        _DetailRow(
                          label: texts.t('verified'),
                          value: passenger.isVerified
                              ? texts.t('yes')
                              : texts.t('no'),
                        ),
                        _DetailRow(
                          label: texts.t('online'),
                          value: passenger.isOnline
                              ? texts.t('yes')
                              : texts.t('no'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: texts.t('location'),
                      children: [
                        _DetailRow(
                          label: texts.t('pickup'),
                          value: passenger.pickupLocationDescription,
                        ),
                        _DetailRow(
                          label: texts.t('latitude'),
                          value: passenger.latitude?.toString() ?? '',
                        ),
                        _DetailRow(
                          label: texts.t('longitude'),
                          value: passenger.longitude?.toString() ?? '',
                        ),
                        _DetailRow(
                          label: texts.t('lastUpdate'),
                          value: _formatDate(passenger.lastLocationUpdate),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: texts.t('dates'),
                      children: [
                        _DetailRow(
                          label: texts.t('createdAt'),
                          value: _formatDate(passenger.createdAt),
                        ),
                        _DetailRow(
                          label: texts.t('updatedAt'),
                          value: _formatDate(passenger.updatedAt),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: NavigoColors.primaryOrange,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(texts.t('close')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReportsPanel extends StatelessWidget {
  final AdminDashboardService service;

  const _ReportsPanel({required this.service});

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 24, 16),
      child: Container(
        decoration: _cardDecoration(
          radius: 28,
        ).copyWith(color: NavigoColors.surfaceWhite),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    texts.t('reportsSentToAdmin'),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    texts.t('reportsSentSubtitle'),
                    style: NavigoTextStyles.bodyMedium,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<AdminReportItem>>(
                stream: service.adminReportsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        '${texts.t('errorLoadingReports')}: ${snapshot.error}',
                      ),
                    );
                  }

                  final reports = snapshot.data ?? [];

                  if (reports.isEmpty) {
                    return Center(
                      child: Text(
                        texts.t('noReportsSent'),
                        style: NavigoTextStyles.bodyMedium,
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: reports.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final report = reports[index];

                      return _ReportTile(
                        report: report,
                        onTap: () => _showReportDetails(context, report),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDetails(BuildContext context, AdminReportItem report) {
    final texts = context.texts;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 56,
            vertical: 40,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.purple.withValues(
                            alpha: 0.12,
                          ),
                          child: const Icon(
                            Icons.description_rounded,
                            color: Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            texts.t('reportDetails'),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: texts.t('close'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _DetailSection(
                      title: texts.t('reportInformation'),
                      children: [
                        _DetailRow(
                          label: texts.t('status'),
                          value: _formatStatus(report.status),
                        ),
                        _DetailRow(
                          label: texts.t('createdAt'),
                          value: _formatDate(report.createdAt),
                        ),
                        _DetailRow(
                          label: texts.t('sentToAdminAt'),
                          value: _formatDate(report.sentToAdminAt),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: texts.t('senderAndRoute'),
                      children: [
                        _DetailRow(
                          label: texts.t('sender'),
                          value: report.senderName,
                        ),
                        _DetailRow(
                          label: texts.t('senderRole'),
                          value: report.senderRole,
                        ),
                        _DetailRow(
                          label: texts.t('route'),
                          value: _localizedRouteName(
                            context,
                            label: report.routeLabel,
                            fallback: '',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: texts.t('message'),
                      children: [
                        SelectableText(
                          report.message,
                          style: NavigoTextStyles.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: NavigoColors.primaryOrange,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(texts.t('close')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReportTile extends StatelessWidget {
  final AdminReportItem report;
  final VoidCallback onTap;

  const _ReportTile({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NavigoColors.borderLight),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: Colors.purple.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.description_rounded,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.senderName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _Chip(
                          label: _formatStatus(report.status),
                          color: Colors.purple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(report.message, style: NavigoTextStyles.bodyMedium),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        _ReportMeta(
                          icon: Icons.badge_rounded,
                          text: report.senderRole,
                        ),
                        _ReportMeta(
                          icon: Icons.route_rounded,
                          text: _localizedRouteName(
                            context,
                            label: report.routeLabel,
                            fallback: '',
                          ),
                        ),
                        _ReportMeta(
                          icon: Icons.schedule_rounded,
                          text: _formatDate(
                            report.sentToAdminAt ?? report.createdAt,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.open_in_new_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NavigoColors.backgroundAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NavigoColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: NavigoTextStyles.titleSmall),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final displayValue = value.isEmpty ? '-' : value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: SelectableText(
              displayValue,
              textDirection: _looksNumeric(displayValue)
                  ? TextDirection.ltr
                  : null,
              textAlign: _looksNumeric(displayValue)
                  ? TextAlign.left
                  : TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }
}

class _LtrText extends StatelessWidget {
  final String value;
  final TextStyle? style;

  //  const _LtrText(this.value, {this.style});
  const _LtrText(this.value, {this.style});
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(value, textAlign: TextAlign.left, style: style),
    );
  }
}

class _ReportMeta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ReportMeta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: NavigoColors.textGray),
        const SizedBox(width: 5),
        Text(text, style: NavigoTextStyles.bodySmall),
      ],
    );
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.selectedSection,
    required this.isLoggingOut,
    required this.onDashboard,
    required this.onDrivers,
    required this.onRoutes,
    required this.onRouteManagers,
    required this.onTrips,
    required this.onPassengers,
    required this.onLogout,
    required this.onReports,
  });

  final _AdminSection selectedSection;
  final bool isLoggingOut;
  final VoidCallback onDashboard;
  final VoidCallback onDrivers;
  final VoidCallback onRoutes;
  final VoidCallback onRouteManagers;
  final VoidCallback onTrips;
  final VoidCallback onPassengers;
  final VoidCallback onLogout;
  final VoidCallback onReports;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  bool _isAccountExpanded = false;

  void _toggleAccountCard() {
    setState(() => _isAccountExpanded = !_isAccountExpanded);
  }

  void _toggleLanguage() {
    final controller = AppControllerScope.of(context).languageController;
    final nextLanguage = controller.locale.languageCode == 'ar' ? 'en' : 'ar';
    controller.setLanguage(nextLanguage);
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    final languageController = AppControllerScope.of(
      context,
    ).languageController;
    final nextLanguage = languageController.locale.languageCode == 'ar'
        ? texts.t('english')
        : texts.t('arabic');

    return Container(
      width: 260,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(radius: 22),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: NavigoColors.primaryOrange,
                  child: Icon(Icons.directions_bus, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        texts.t('navigoAdmin'),
                        style: NavigoTextStyles.titleSmall,
                      ),
                      Text(
                        texts.t('systemControlPanel'),
                        style: NavigoTextStyles.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            _MenuItem(
              icon: Icons.dashboard_rounded,
              title: texts.t('dashboard'),
              selected: widget.selectedSection == _AdminSection.dashboard,
              onTap: widget.onDashboard,
            ),
            _MenuItem(
              icon: Icons.person_rounded,
              title: texts.t('drivers'),
              selected: widget.selectedSection == _AdminSection.drivers,
              onTap: widget.onDrivers,
            ),
            _MenuItem(
              icon: Icons.route_rounded,
              title: texts.t('routes'),
              selected: widget.selectedSection == _AdminSection.routes,
              onTap: widget.onRoutes,
            ),
            _MenuItem(
              icon: Icons.manage_accounts_rounded,
              title: texts.t('routeManagers'),
              selected: widget.selectedSection == _AdminSection.routeManagers,
              onTap: widget.onRouteManagers,
            ),
            _MenuItem(
              icon: Icons.directions_bus_rounded,
              title: texts.t('trips'),
              selected: widget.selectedSection == _AdminSection.trips,
              onTap: widget.onTrips,
            ),
            _MenuItem(
              icon: Icons.people_alt_rounded,
              title: texts.t('passengers'),
              selected: widget.selectedSection == _AdminSection.passengers,
              onTap: widget.onPassengers,
            ),
            _MenuItem(
              icon: Icons.bar_chart_rounded,
              title: texts.t('reports'),
              selected: widget.selectedSection == _AdminSection.reports,
              onTap: widget.onReports,
            ),

            const SizedBox(height: 18),

            _MenuItem(
              icon: Icons.logout_rounded,
              title: widget.isLoggingOut
                  ? texts.t('loggingOut')
                  : texts.t('logout'),
              onTap: widget.isLoggingOut ? null : widget.onLogout,
              trailing: widget.isLoggingOut
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),

            const SizedBox(height: 16),

            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _toggleAccountCard,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: NavigoColors.backgroundAlt,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: NavigoColors.borderLight),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: NavigoColors.primaryOrange,
                        child: Text('A', style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              texts.t('admin'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              texts.t('adminAccount'),
                              style: NavigoTextStyles.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _isAccountExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: [
                    _AccountActionButton(
                      icon: Icons.lock_reset_rounded,
                      title: texts.t('changePassword'),
                      onTap: () => showAdminAccountDialog(context),
                    ),
                    const SizedBox(height: 8),
                    _AccountActionButton(
                      icon: Icons.language_rounded,
                      title: '${texts.t('language')}: $nextLanguage',
                      onTap: _toggleLanguage,
                    ),
                  ],
                ),
              ),
              crossFadeState: _isAccountExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
              sizeCurve: Curves.easeOut,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _AccountActionButton({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(title, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor: NavigoColors.textDark,
          side: const BorderSide(color: NavigoColors.borderLight),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _MenuItem({
    required this.icon,
    required this.title,
    this.selected = false,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected
            ? NavigoColors.primaryOrange.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: selected ? NavigoColors.primaryOrange : NavigoColors.textGray,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected
                ? NavigoColors.primaryOrange
                : NavigoColors.textDark,
          ),
        ),
        trailing: trailing,
      ),
    );
  }
}

class _CreateRouteManagerDialog extends StatefulWidget {
  final AdminDashboardService service;

  const _CreateRouteManagerDialog({required this.service});

  @override
  State<_CreateRouteManagerDialog> createState() =>
      _CreateRouteManagerDialogState();
}

class _CreateRouteManagerDialogState extends State<_CreateRouteManagerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _selectedPhonePrefix = '+970';
  String? _selectedRouteId;
  String? _emailError;
  String? _phoneError;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveRouteManager() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;

    setState(() {
      _emailError = null;
      _phoneError = null;
      _isSaving = true;
    });
    try {
      await widget.service.createRouteManager(
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        email: _emailController.text,
        phone: '$_selectedPhonePrefix${_phoneController.text.trim()}',
        password: _passwordController.text,
        routeId: _selectedRouteId!,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      if (_showContactFieldError(e)) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  bool _showContactFieldError(Object error) {
    final message = _friendlyError(error);
    if (message.toLowerCase().contains('phone number')) {
      setState(() => _phoneError = context.texts.t('phoneAlreadyExists'));
      _formKey.currentState?.validate();
      return true;
    }
    if (message.toLowerCase().contains('email') ||
        message.contains('email-already-in-use')) {
      setState(() => _emailError = context.texts.t('emailAlreadyExists'));
      _formKey.currentState?.validate();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          texts.t('createRouteManager'),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: texts.t('close'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstNameController,
                          decoration: NavigoDecorations.kInputDecoration
                              .copyWith(
                                labelText: texts.t('firstName'),
                                prefixIcon: const Icon(Icons.person_rounded),
                                fillColor: Colors.white,
                              ),
                          validator: (value) => _validateName(
                            value,
                            texts.t('firstName'),
                            context,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextFormField(
                          controller: _lastNameController,
                          decoration: NavigoDecorations.kInputDecoration
                              .copyWith(
                                labelText: texts.t('lastName'),
                                prefixIcon: const Icon(Icons.badge_outlined),
                                fillColor: Colors.white,
                              ),
                          validator: (value) => _validateName(
                            value,
                            texts.t('lastName'),
                            context,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) {
                      if (_emailError != null) {
                        setState(() => _emailError = null);
                      }
                    },
                    decoration: NavigoDecorations.kInputDecoration.copyWith(
                      labelText: texts.t('email'),
                      prefixIcon: const Icon(Icons.email_rounded),
                      fillColor: Colors.white,
                    ),
                    validator: (value) =>
                        _emailError ?? _validateEmail(value, context),
                  ),
                  const SizedBox(height: 14),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 150,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedPhonePrefix,
                            decoration: NavigoDecorations.kInputDecoration
                                .copyWith(
                                  labelText: texts.t('code'),
                                  prefixIcon: const Icon(Icons.phone_rounded),
                                  fillColor: Colors.white,
                                ),
                            items: const [
                              DropdownMenuItem(
                                value: '+970',
                                child: Text(
                                  '+970',
                                  textDirection: TextDirection.ltr,
                                ),
                              ),
                              DropdownMenuItem(
                                value: '+972',
                                child: Text(
                                  '+972',
                                  textDirection: TextDirection.ltr,
                                ),
                              ),
                            ],
                            onChanged: _isSaving
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(
                                      () => _selectedPhonePrefix = value,
                                    );
                                  },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.left,
                            onChanged: (_) {
                              if (_phoneError != null) {
                                setState(() => _phoneError = null);
                              }
                            },
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(9),
                            ],
                            decoration: NavigoDecorations.kInputDecoration
                                .copyWith(
                                  labelText: texts.t('phoneNumber'),
                                  hintText: texts.t('nineDigits'),
                                  fillColor: Colors.white,
                                ),
                            validator: (value) =>
                                _phoneError ??
                                _validatePhoneDigits(value, context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(texts.t('phoneRule'), style: NavigoTextStyles.bodySmall),
                  const SizedBox(height: 14),
                  Text(
                    texts.t('passwordRules'),
                    style: NavigoTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: NavigoDecorations.kInputDecoration
                              .copyWith(
                                labelText: texts.t('password'),
                                prefixIcon: const Icon(Icons.lock_rounded),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    );
                                  },
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: NavigoColors.textMuted,
                                  ),
                                  tooltip: _obscurePassword
                                      ? texts.t('show')
                                      : texts.t('hide'),
                                ),
                                fillColor: Colors.white,
                              ),
                          validator: (value) =>
                              _validatePassword(value, context),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          decoration: NavigoDecorations.kInputDecoration
                              .copyWith(
                                labelText: texts.t('confirmPassword'),
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(
                                      () => _obscureConfirmPassword =
                                          !_obscureConfirmPassword,
                                    );
                                  },
                                  icon: Icon(
                                    _obscureConfirmPassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: NavigoColors.textMuted,
                                  ),
                                  tooltip: _obscureConfirmPassword
                                      ? texts.t('show')
                                      : texts.t('hide'),
                                ),
                                fillColor: Colors.white,
                              ),
                          validator: (value) {
                            if (value != _passwordController.text) {
                              return texts.t('passwordsDoNotMatch');
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  StreamBuilder<List<AdminRouteItem>>(
                    stream: widget.service.adminRoutesStream(),
                    builder: (context, snapshot) {
                      final routes = snapshot.data ?? const <AdminRouteItem>[];
                      final isLoading =
                          snapshot.connectionState == ConnectionState.waiting;

                      return DropdownButtonFormField<String>(
                        initialValue: _selectedRouteId,
                        items: routes
                            .map(
                              (route) => DropdownMenuItem(
                                value: route.routeId,
                                child: Text(
                                  _localizedRouteName(
                                    context,
                                    start: route.startPoint,
                                    end: route.endPoint,
                                    fallback: '',
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving || routes.isEmpty
                            ? null
                            : (value) {
                                setState(() => _selectedRouteId = value);
                              },
                        decoration: NavigoDecorations.kInputDecoration.copyWith(
                          labelText: isLoading
                              ? texts.t('loadingRoutes')
                              : texts.t('route'),
                          prefixIcon: const Icon(Icons.route_rounded),
                          fillColor: Colors.white,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return texts.t('selectRoute');
                          }
                          return null;
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveRouteManager,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(
                        _isSaving
                            ? texts.t('creating')
                            : texts.t('createRouteManager'),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: NavigoColors.primaryOrange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditRouteManagerDialog extends StatefulWidget {
  final AdminDashboardService service;
  final AdminRouteManagerItem manager;

  const _EditRouteManagerDialog({required this.service, required this.manager});

  @override
  State<_EditRouteManagerDialog> createState() =>
      _EditRouteManagerDialogState();
}

class _EditRouteManagerDialogState extends State<_EditRouteManagerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late String _selectedPhonePrefix;
  String? _selectedRouteId;
  String? _emailError;
  String? _phoneError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final fallbackParts = widget.manager.fullName.trim().split(' ');
    final fallbackFirstName = fallbackParts.isEmpty ? '' : fallbackParts.first;
    final fallbackLastName = fallbackParts.length <= 1
        ? ''
        : fallbackParts.sublist(1).join(' ');

    _firstNameController = TextEditingController(
      text: widget.manager.firstName.isEmpty
          ? fallbackFirstName
          : widget.manager.firstName,
    );
    _lastNameController = TextEditingController(
      text: widget.manager.lastName.isEmpty
          ? fallbackLastName
          : widget.manager.lastName,
    );
    _emailController = TextEditingController(text: widget.manager.email);
    final phoneParts = _splitPhoneNumber(widget.manager.phone);
    _selectedPhonePrefix = phoneParts.prefix;
    _phoneController = TextEditingController(text: phoneParts.digits);
    _selectedRouteId = widget.manager.routeId.isEmpty
        ? null
        : widget.manager.routeId;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveRouteManager() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;

    setState(() {
      _emailError = null;
      _phoneError = null;
      _isSaving = true;
    });
    try {
      await widget.service.updateRouteManager(
        managerId: widget.manager.managerId,
        userId: widget.manager.userId,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        email: _emailController.text,
        phone: '$_selectedPhonePrefix${_phoneController.text.trim()}',
        routeId: _selectedRouteId!,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      if (_showContactFieldError(e)) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  bool _showContactFieldError(Object error) {
    final message = _friendlyError(error);
    if (message.toLowerCase().contains('phone number')) {
      setState(() => _phoneError = context.texts.t('phoneAlreadyExists'));
      _formKey.currentState?.validate();
      return true;
    }
    if (message.toLowerCase().contains('email')) {
      setState(() => _emailError = context.texts.t('emailAlreadyExists'));
      _formKey.currentState?.validate();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          texts.t('editRouteManager'),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: texts.t('close'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstNameController,
                          decoration: NavigoDecorations.kInputDecoration
                              .copyWith(
                                labelText: texts.t('firstName'),
                                prefixIcon: const Icon(Icons.person_rounded),
                                fillColor: Colors.white,
                              ),
                          validator: (value) => _validateName(
                            value,
                            texts.t('firstName'),
                            context,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextFormField(
                          controller: _lastNameController,
                          decoration: NavigoDecorations.kInputDecoration
                              .copyWith(
                                labelText: texts.t('lastName'),
                                prefixIcon: const Icon(Icons.badge_outlined),
                                fillColor: Colors.white,
                              ),
                          validator: (value) => _validateName(
                            value,
                            texts.t('lastName'),
                            context,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) {
                      if (_emailError != null) {
                        setState(() => _emailError = null);
                      }
                    },
                    decoration: NavigoDecorations.kInputDecoration.copyWith(
                      labelText: texts.t('email'),
                      prefixIcon: const Icon(Icons.email_rounded),
                      fillColor: Colors.white,
                    ),
                    validator: (value) =>
                        _emailError ?? _validateEmail(value, context),
                  ),
                  const SizedBox(height: 14),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 150,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedPhonePrefix,
                            decoration: NavigoDecorations.kInputDecoration
                                .copyWith(
                                  labelText: texts.t('code'),
                                  prefixIcon: const Icon(Icons.phone_rounded),
                                  fillColor: Colors.white,
                                ),
                            items: const [
                              DropdownMenuItem(
                                value: '+970',
                                child: Text(
                                  '+970',
                                  textDirection: TextDirection.ltr,
                                ),
                              ),
                              DropdownMenuItem(
                                value: '+972',
                                child: Text(
                                  '+972',
                                  textDirection: TextDirection.ltr,
                                ),
                              ),
                            ],
                            onChanged: _isSaving
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(
                                      () => _selectedPhonePrefix = value,
                                    );
                                  },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.left,
                            onChanged: (_) {
                              if (_phoneError != null) {
                                setState(() => _phoneError = null);
                              }
                            },
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(9),
                            ],
                            decoration: NavigoDecorations.kInputDecoration
                                .copyWith(
                                  labelText: texts.t('phoneNumber'),
                                  hintText: texts.t('nineDigits'),
                                  fillColor: Colors.white,
                                ),
                            validator: (value) =>
                                _phoneError ??
                                _validatePhoneDigits(value, context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(texts.t('phoneRule'), style: NavigoTextStyles.bodySmall),
                  const SizedBox(height: 14),
                  StreamBuilder<List<AdminRouteItem>>(
                    stream: widget.service.adminRoutesStream(),
                    builder: (context, snapshot) {
                      final routes = snapshot.data ?? const <AdminRouteItem>[];
                      final isLoading =
                          snapshot.connectionState == ConnectionState.waiting;
                      final dropdownRouteId =
                          routes.any(
                            (route) => route.routeId == _selectedRouteId,
                          )
                          ? _selectedRouteId
                          : null;

                      return DropdownButtonFormField<String>(
                        initialValue: dropdownRouteId,
                        items: routes
                            .map(
                              (route) => DropdownMenuItem(
                                value: route.routeId,
                                child: Text(
                                  _localizedRouteName(
                                    context,
                                    start: route.startPoint,
                                    end: route.endPoint,
                                    fallback: '',
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving || routes.isEmpty
                            ? null
                            : (value) {
                                setState(() => _selectedRouteId = value);
                              },
                        decoration: NavigoDecorations.kInputDecoration.copyWith(
                          labelText: isLoading
                              ? texts.t('loadingRoutes')
                              : texts.t('route'),
                          prefixIcon: const Icon(Icons.route_rounded),
                          fillColor: Colors.white,
                        ),
                        validator: (value) {
                          if (_selectedRouteId == null ||
                              _selectedRouteId!.trim().isEmpty) {
                            return texts.t('selectRoute');
                          }
                          return null;
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveRouteManager,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _isSaving ? texts.t('saving') : texts.t('saveChanges'),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: NavigoColors.primaryOrange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneParts {
  final String prefix;
  final String digits;

  const _PhoneParts({required this.prefix, required this.digits});
}

_PhoneParts _splitPhoneNumber(String phone) {
  final cleanPhone = phone.trim().replaceAll(RegExp(r'\s+'), '');
  if (cleanPhone.startsWith('+972')) {
    return _PhoneParts(prefix: '+972', digits: cleanPhone.substring(4));
  }
  if (cleanPhone.startsWith('+970')) {
    return _PhoneParts(prefix: '+970', digits: cleanPhone.substring(4));
  }

  final digitsOnly = cleanPhone.replaceAll(RegExp(r'\D'), '');
  return _PhoneParts(
    prefix: '+970',
    digits: digitsOnly.length > 9 ? digitsOnly.substring(0, 9) : digitsOnly,
  );
}

String? _validateName(String? value, String label, BuildContext context) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) {
    return context.texts.t('nameRequired').replaceAll('{label}', label);
  }
  if (!RegExp(r"^[A-Za-z\u0600-\u06FF\s'-]+$").hasMatch(name)) {
    return context.texts.t('nameLettersOnly').replaceAll('{label}', label);
  }
  return null;
}

String? _validateEmail(String? value, BuildContext context) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return context.texts.t('emailRequired');
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return context.texts.t('validEmail');
  }
  return null;
}

String? _validatePhoneDigits(String? value, BuildContext context) {
  final digits = value?.trim() ?? '';
  if (digits.isEmpty) return context.texts.t('phoneRequired');
  if (!RegExp(r'^\d{9}$').hasMatch(digits)) {
    return context.texts.t('phoneNineNumbers');
  }
  return null;
}

String? _validatePassword(String? value, BuildContext context) {
  final password = value ?? '';
  if (password.length < 8) return context.texts.t('passwordEight');
  if (!RegExp(r'[A-Z]').hasMatch(password)) {
    return context.texts.t('passwordUppercase');
  }
  if (!RegExp(r'[a-z]').hasMatch(password)) {
    return context.texts.t('passwordLowercase');
  }
  if (!RegExp(r'\d').hasMatch(password)) {
    return context.texts.t('passwordNumber');
  }
  if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
    return context.texts.t('passwordSpecial');
  }
  return null;
}

String _friendlyError(Object error) {
  final message = error.toString();
  return message
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '')
      .trim();
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                texts.t('dashboard'),
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                texts.t('welcomeBackAdmin'),
                style: NavigoTextStyles.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.searchHint,
    required this.onSearchChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(34),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: NavigoTextStyles.bodyMedium),
              ],
            ),
          ),
          SizedBox(
            width: trailing == null ? 380 : 320,
            child: TextField(
              onChanged: onSearchChanged,
              decoration: NavigoDecorations.kInputDecoration.copyWith(
                hintText: searchHint,
                prefixIcon: const Icon(Icons.search),
                fillColor: Colors.white,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 14), trailing!],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconBox(icon: icon, color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              _Chip(label: label, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: _cardDecoration(),
          child: Row(
            children: [
              _IconBox(icon: icon, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    Text(subtitle, style: NavigoTextStyles.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PieChartCard extends StatelessWidget {
  final int totalDrivers;
  final int pendingDrivers;
  final int totalUsers;

  const _PieChartCard({
    required this.totalDrivers,
    required this.pendingDrivers,
    required this.totalUsers,
  });

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    final approvedDrivers = totalDrivers - pendingDrivers < 0
        ? 0
        : totalDrivers - pendingDrivers;

    final passengers = totalUsers - totalDrivers;
    final safePassengers = passengers < 0 ? 0 : passengers;

    final total = approvedDrivers + pendingDrivers + safePassengers;

    return Container(
      height: 360,
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texts.t('systemOverview'), style: NavigoTextStyles.titleSmall),
          const SizedBox(height: 20),

          Expanded(
            child: Center(
              child: SizedBox(
                height: 170,
                width: 170,
                child: CustomPaint(
                  painter: _PieChartPainter(
                    approvedDrivers: approvedDrivers,
                    pendingDrivers: pendingDrivers,
                    passengers: safePassengers,
                    total: total == 0 ? 1 : total,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          _LegendItem(
            color: NavigoColors.accentGreen,
            title: texts.t('approvedDrivers'),
            value: approvedDrivers.toString(),
          ),
          const SizedBox(height: 10),
          _LegendItem(
            color: NavigoColors.primaryOrange,
            title: texts.t('pendingDrivers'),
            value: pendingDrivers.toString(),
          ),
          const SizedBox(height: 10),
          _LegendItem(
            color: NavigoColors.accentBlue,
            title: texts.t('passengersUsers'),
            value: safePassengers.toString(),
          ),
        ],
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final int approvedDrivers;
  final int pendingDrivers;
  final int passengers;
  final int total;

  _PieChartPainter({
    required this.approvedDrivers,
    required this.pendingDrivers,
    required this.passengers,
    required this.total,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    double startAngle = -1.5708;

    void drawSection(int value, Color color) {
      final sweepAngle = (value / total) * 6.28318;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      startAngle += sweepAngle;
    }

    drawSection(approvedDrivers, NavigoColors.accentGreen);
    drawSection(pendingDrivers, NavigoColors.primaryOrange);
    drawSection(passengers, NavigoColors.accentBlue);

    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.28,
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return approvedDrivers != oldDelegate.approvedDrivers ||
        pendingDrivers != oldDelegate.pendingDrivers ||
        passengers != oldDelegate.passengers ||
        total != oldDelegate.total;
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String title;
  final String value;

  const _LegendItem({
    required this.color,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 12,
          width: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _PendingApprovalsCard extends StatelessWidget {
  final List<AdminApprovalItem> approvals;
  final Set<String> busyApprovalIds;
  final Future<void> Function(AdminApprovalItem item) onApprove;
  final Future<void> Function(AdminApprovalItem item) onReject;

  const _PendingApprovalsCard({
    required this.approvals,
    required this.busyApprovalIds,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Container(
      constraints: const BoxConstraints(minHeight: 420),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(22),
            child: Text(
              texts.t('pendingApprovals'),
              style: NavigoTextStyles.titleSmall,
            ),
          ),

          if (approvals.isEmpty)
            Padding(
              padding: const EdgeInsets.all(22),
              child: Text(
                texts.t('noPendingApprovals'),
                style: NavigoTextStyles.bodySmall,
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  NavigoColors.backgroundAlt,
                ),
                columns: [
                  DataColumn(label: Text(texts.t('type'))),
                  DataColumn(label: Text(texts.t('name'))),
                  DataColumn(label: Text(texts.t('details'))),
                  DataColumn(label: Text(texts.t('status'))),
                  DataColumn(label: Text(texts.t('action'))),
                ],
                rows: approvals.map((item) {
                  final isBusy = busyApprovalIds.contains(item.id);
                  return DataRow(
                    cells: [
                      DataCell(Text(item.type)),
                      DataCell(
                        Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataCell(Text(item.details)),
                      DataCell(
                        _Chip(
                          label: item.status,
                          color: NavigoColors.primaryOrange,
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isBusy)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else ...[
                              FilledButton.icon(
                                onPressed: () => onApprove(item),
                                icon: const Icon(Icons.check, size: 16),
                                label: Text(texts.t('approve')),
                                style: FilledButton.styleFrom(
                                  backgroundColor: NavigoColors.accentGreen,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () => onReject(item),
                                icon: const Icon(Icons.close, size: 16),
                                label: Text(texts.t('reject')),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: NavigoColors.accentRed,
                                  side: const BorderSide(
                                    color: NavigoColors.accentRed,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBox({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

String _formatStatus(String status) {
  return status
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _localizedTripStatus(BuildContext context, String status) {
  final normalized = status.trim().toLowerCase().replaceAll('-', '_');
  final texts = context.texts;

  return switch (normalized) {
    'scheduled' => texts.t('tripStatusScheduled'),
    'ongoing' || 'ontrip' || 'on_trip' => texts.t('tripStatusOngoing'),
    'active' => texts.t('tripStatusActive'),
    'started' => texts.t('tripStatusStarted'),
    'completed' || 'finished' => texts.t('tripStatusCompleted'),
    'cancelled' || 'canceled' => texts.t('tripStatusCancelled'),
    'pending' => texts.t('tripStatusPending'),
    'assigned' => texts.t('tripStatusAssigned'),
    'unassigned' => texts.t('tripStatusUnassigned'),
    _ => _formatStatus(status),
  };
}

String _localizedVehicleType(BuildContext context, String value) {
  final clean = value.trim();
  if (clean.isEmpty) return '-';
  if (context.texts.locale.languageCode != 'ar') return _formatStatus(clean);

  final normalized = clean
      .toLowerCase()
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (normalized == 'microbus' ||
      normalized == 'micro bus' ||
      normalized == 'microbus 14' ||
      normalized == 'microbus 45' ||
      normalized == 'ford') {
    return 'فورد';
  }

  if (normalized == 'bus' || normalized == 'bus 14' || normalized == 'bus 45') {
    final number = RegExp(r'\d+').firstMatch(normalized)?.group(0);
    return number == null ? 'حافلة' : 'حافلة $number';
  }

  return clean;
}

String _localizedRouteName(
  BuildContext context, {
  String? label,
  String? start,
  String? end,
  String? fallback,
}) {
  final isArabic = context.texts.locale.languageCode == 'ar';
  final cleanStart = start?.trim() ?? '';
  final cleanEnd = end?.trim() ?? '';

  if (cleanStart.isNotEmpty || cleanEnd.isNotEmpty) {
    final localizedStart = _localizedPlaceName(context, cleanStart);
    final localizedEnd = _localizedPlaceName(context, cleanEnd);

    if (localizedStart.isNotEmpty && localizedEnd.isNotEmpty) {
      return isArabic
          ? '$localizedStart إلى $localizedEnd'
          : '$localizedStart to $localizedEnd';
    }
    if (localizedStart.isNotEmpty) return localizedStart;
    if (localizedEnd.isNotEmpty) return localizedEnd;
  }

  final cleanLabel = label?.trim() ?? '';
  if (cleanLabel.isEmpty) return _dash(fallback ?? '');
  if (!isArabic) return cleanLabel;

  final separatorPattern = RegExp(
    r'\s*(?:<[-\s]*>|<----->|↔|→|->|–|\s-\s| to )\s*',
    caseSensitive: false,
  );
  final parts = cleanLabel
      .split(separatorPattern)
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();

  if (parts.length >= 2) {
    return parts
        .map((part) => _localizedPlaceName(context, part))
        .join(' إلى ');
  }

  return _localizedPlaceName(
    context,
    cleanLabel,
  ).replaceAll(RegExp(r'\s+to\s+', caseSensitive: false), ' إلى ');
}

String _localizedPlaceName(BuildContext context, String value) {
  final clean = value.trim();
  if (clean.isEmpty) return '';
  if (context.texts.locale.languageCode != 'ar') return clean;

  final normalized = clean
      .toLowerCase()
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  const arabicPlaces = {
    'jenin': 'جنين',
    'nablus': 'نابلس',
    'ramallah': 'رام الله',
    'al bireh': 'البيرة',
    'albireh': 'البيرة',
    'birzeit': 'بيرزيت',
    'bir zeit': 'بيرزيت',
    'rawabi': 'روابي',
    'tulkarm': 'طولكرم',
    'tul karem': 'طولكرم',
    'qalqilya': 'قلقيلية',
    'salfit': 'سلفيت',
    'jericho': 'أريحا',
    'bethlehem': 'بيت لحم',
    'beit lehem': 'بيت لحم',
    'hebron': 'الخليل',
    'al khalil': 'الخليل',
    'jerusalem': 'القدس',
    'al quds': 'القدس',
    'gaza': 'غزة',
    'rafah': 'رفح',
    'khan yunis': 'خان يونس',
    'tubas': 'طوباس',
    'ya bad': 'يعبد',
    'yabad': 'يعبد',
    'qabatiya': 'قباطية',
    'arraba': 'عرابة',
  };

  return arabicPlaces[normalized] ?? clean;
}

String _formatDate(DateTime? date) {
  if (date == null) return 'No date';

  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');

  return '${date.year}-$month-$day $hour:$minute';
}

String _dash(String value) {
  return value.trim().isEmpty ? '-' : value;
}

bool _looksNumeric(String value) {
  final clean = value.trim();
  if (clean.isEmpty || clean == '-') return false;
  return RegExp(r'[0-9]').hasMatch(clean) &&
      !RegExp(r'[\u0600-\u06FF]').hasMatch(clean);
}

Color _tripStatusColor(String status) {
  final normalized = status.toLowerCase();

  if (normalized == 'ongoing' ||
      normalized == 'ontrip' ||
      normalized == 'active' ||
      normalized == 'started') {
    return NavigoColors.accentGreen;
  }

  if (normalized == 'cancelled' || normalized == 'canceled') {
    return NavigoColors.accentRed;
  }

  if (normalized == 'completed' || normalized == 'finished') {
    return NavigoColors.accentBlue;
  }

  return NavigoColors.primaryOrange;
}

BoxDecoration _cardDecoration({double radius = 18}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: NavigoColors.borderLight),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}
