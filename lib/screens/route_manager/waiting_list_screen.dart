import 'package:flutter/material.dart';

import '../../localization/localization_x.dart';
import '../../models/waiting_trip_request.dart';
import '../../services/route_manager_route_id.dart';
import '../../services/waiting_trip_request_service.dart';
import '../../theme/app_theme.dart';
import 'add_schedule_slot_screen.dart';
import 'route_manager_notification_compose.dart';
import 'route_manager_nav_bar.dart';

class WaitingListScreen extends StatefulWidget {
  const WaitingListScreen({super.key});

  @override
  State<WaitingListScreen> createState() => _WaitingListScreenState();
}

class _WaitingListScreenState extends State<WaitingListScreen> {
  final WaitingTripRequestService _service = WaitingTripRequestService();

  String? _routeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    final routeId = await resolveManagedRouteId();
    if (!mounted) return;
    setState(() {
      _routeId = routeId;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final routeId = _routeId;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: NavigoColors.backgroundLight,
        bottomNavigationBar: const RouteManagerNavBar(currentIndex: 2),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NavigoDecorations.topBar3(
                onBack: () => Navigator.pop(context),
                onNotification: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RouteManagerNotificationCompose(),
                  ),
                ),
              ),
              _buildHeader(context),
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? _StatePanel(
                        icon: Icons.groups_2_outlined,
                        message: context.texts.t('loading'),
                        showLoader: true,
                      )
                    : (routeId == null || routeId.trim().isEmpty)
                    ? _StatePanel(
                        icon: Icons.route_outlined,
                        message: context.texts.t('noRouteLinkedAccount'),
                      )
                    : StreamBuilder<List<WaitingTripGroup>>(
                        stream: _service.watchPendingGroupsForRoute(routeId),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return _StatePanel(
                              icon: Icons.groups_2_outlined,
                              message: context.texts.t('loading'),
                              showLoader: true,
                            );
                          }
                          if (snapshot.hasError) {
                            return _StatePanel(
                              icon: Icons.error_outline,
                              message: snapshot.error.toString(),
                            );
                          }

                          final groups = snapshot.data ?? const [];
                          if (groups.isEmpty) {
                            return _StatePanel(
                              icon: Icons.event_available_outlined,
                              message: context.texts.t('noWaitingListRequests'),
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            itemCount: groups.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final group = groups[index];
                              return _WaitingGroupCard(
                                group: group,
                                requestsStream: _service.watchRequestsForGroup(
                                  group.groupId,
                                ),
                                onViewRequests: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        WaitingGroupDetailsScreen(group: group),
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
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NavigoSizes.screenPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.texts.t('waitingList'),
            style: NavigoTextStyles.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            context.texts.t('waitingListSubtitle'),
            style: NavigoTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }
}

class WaitingGroupDetailsScreen extends StatelessWidget {
  WaitingGroupDetailsScreen({super.key, required this.group});

  final WaitingTripGroup group;
  final WaitingTripRequestService _service = WaitingTripRequestService();

  void _openCreateTrip(
    BuildContext context,
    List<WaitingTripRequest> requests,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddScheduleSlotScreen(
          routeId: group.routeId,
          waitingTripGroupId: group.groupId,
          waitingTripRequestIds: requests
              .map((request) => request.requestId)
              .toList(),
          waitingPickupLocations: requests
              .map((request) => request.pickupLocationDescription)
              .where((pickup) => pickup.trim().isNotEmpty)
              .toList(),
          initialDepartureAt: group.departureAt,
          initialCapacity: group.requestedSeatCount,
          initialVehicleType: group.vehicleType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: NavigoColors.backgroundLight,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NavigoDecorations.topBar3(
                onBack: () => Navigator.pop(context),
                onNotification: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RouteManagerNotificationCompose(),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<WaitingTripRequest>>(
                  stream: _service.watchRequestsForGroup(group.groupId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return _StatePanel(
                        icon: Icons.groups_2_outlined,
                        message: context.texts.t('loading'),
                        showLoader: true,
                      );
                    }
                    if (snapshot.hasError) {
                      return _StatePanel(
                        icon: Icons.error_outline,
                        message: snapshot.error.toString(),
                      );
                    }

                    final requests = snapshot.data ?? const [];
                    return Column(
                      children: [
                        _GroupSummary(
                          group: group,
                          requestCount: requests.isEmpty
                              ? group.passengerCount
                              : requests.length,
                          requestedSeatCount: requests.isEmpty
                              ? group.requestedSeatCount
                              : _totalSeats(requests),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: requests.isEmpty
                              ? _StatePanel(
                                  icon: Icons.person_off_outlined,
                                  message: context.texts.t(
                                    'noWaitingPassengerRequests',
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    20,
                                  ),
                                  itemCount: requests.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    return _WaitingRequestCard(
                                      request: requests[index],
                                    );
                                  },
                                ),
                        ),
                        _CreateGroupTripButton(
                          enabled: requests.isNotEmpty,
                          onPressed: () => _openCreateTrip(context, requests),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _totalSeats(List<WaitingTripRequest> requests) {
    return requests.fold<int>(
      0,
      (sum, request) => sum + request.seatsRequested,
    );
  }
}

class _WaitingGroupCard extends StatelessWidget {
  const _WaitingGroupCard({
    required this.group,
    required this.requestsStream,
    required this.onViewRequests,
  });

  final WaitingTripGroup group;
  final Stream<List<WaitingTripRequest>> requestsStream;
  final VoidCallback onViewRequests;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WaitingTripRequest>>(
      stream: requestsStream,
      builder: (context, snapshot) {
        final requests = snapshot.data ?? const [];
        final requestCount = requests.isEmpty
            ? group.passengerCount
            : requests.length;
        final requestedSeatCount = requests.isEmpty
            ? group.requestedSeatCount
            : requests.fold<int>(
                0,
                (sum, request) => sum + request.seatsRequested,
              );
        final lastRequestAt = requests.isEmpty
            ? null
            : requests
                  .map((request) => request.requestedAt)
                  .reduce((a, b) => a.isAfter(b) ? a : b);

        return Container(
          padding: const EdgeInsets.all(NavigoSizes.cardPadding),
          decoration: NavigoDecorations.kCardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: NavigoDecorations.surfaceDecoration(
                      color: NavigoColors.surfaceWhite,
                      radius: NavigoSizes.inputRadius,
                    ),
                    child: const Icon(
                      Icons.route_outlined,
                      color: NavigoColors.primaryOrange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _routeLabel(group),
                      style: NavigoTextStyles.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _detailRow(
                Icons.calendar_today_outlined,
                context.texts.t('date'),
                _formatDate(group.departureAt),
              ),
              const SizedBox(height: 8),
              _detailRow(
                Icons.access_time,
                context.texts.t('time'),
                'حوالي ${_formatTime(group.departureAt)}',
              ),
              const SizedBox(height: 8),
              _detailRow(
                Icons.groups_2_outlined,
                'عدد الطلبات',
                requestCount.toString(),
              ),
              const SizedBox(height: 8),
              _detailRow(
                Icons.event_seat_outlined,
                context.texts.t('numberOfSeats'),
                requestedSeatCount.toString(),
              ),
              if (lastRequestAt != null) ...[
                const SizedBox(height: 8),
                _detailRow(
                  Icons.update,
                  'آخر طلب',
                  '${_formatDate(lastRequestAt)} ${_formatTime(lastRequestAt)}',
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: NavigoSizes.buttonHeight,
                child: ElevatedButton(
                  onPressed: onViewRequests,
                  style: NavigoDecorations.kPrimaryButtonLargeStyle,
                  child: Text('عرض الطلبات', style: NavigoTextStyles.button),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GroupSummary extends StatelessWidget {
  const _GroupSummary({
    required this.group,
    required this.requestCount,
    required this.requestedSeatCount,
  });

  final WaitingTripGroup group;
  final int requestCount;
  final int requestedSeatCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(NavigoSizes.cardPadding),
      decoration: NavigoDecorations.kCardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_routeLabel(group), style: NavigoTextStyles.titleSmall),
          const SizedBox(height: 12),
          _detailRow(
            Icons.calendar_today_outlined,
            context.texts.t('date'),
            _formatDate(group.departureAt),
          ),
          const SizedBox(height: 8),
          _detailRow(
            Icons.access_time,
            context.texts.t('time'),
            _formatTime(group.departureAt),
          ),
          const SizedBox(height: 8),
          _detailRow(
            Icons.groups_2_outlined,
            'إجمالي الركاب',
            requestCount.toString(),
          ),
          const SizedBox(height: 8),
          _detailRow(
            Icons.event_seat_outlined,
            'إجمالي المقاعد المطلوبة',
            requestedSeatCount.toString(),
          ),
        ],
      ),
    );
  }
}

class _WaitingRequestCard extends StatelessWidget {
  const _WaitingRequestCard({required this.request});

  final WaitingTripRequest request;

  @override
  Widget build(BuildContext context) {
    final pickup = request.pickupLocationDescription.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NavigoSizes.cardPadding),
      decoration: NavigoDecorations.kCardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow(
            Icons.person_outline,
            'اسم الراكب',
            request.passengerName.trim().isEmpty
                ? context.texts.t('unknownUser')
                : request.passengerName.trim(),
          ),
          const SizedBox(height: 8),
          _detailRow(
            Icons.event_seat_outlined,
            'عدد المقاعد المطلوبة',
            request.seatsRequested.toString(),
          ),
          const SizedBox(height: 8),
          _detailRow(
            Icons.location_on_outlined,
            'نقطة الالتقاط',
            pickup.isEmpty ? '-' : pickup,
          ),
          const SizedBox(height: 8),
          _detailRow(
            Icons.schedule,
            'وقت إرسال الطلب',
            '${_formatDate(request.requestedAt)} ${_formatTime(request.requestedAt)}',
          ),
        ],
      ),
    );
  }
}

class _CreateGroupTripButton extends StatelessWidget {
  const _CreateGroupTripButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        color: NavigoColors.backgroundLight,
        child: SizedBox(
          height: NavigoSizes.buttonHeight,
          child: ElevatedButton.icon(
            onPressed: enabled ? onPressed : null,
            style: NavigoDecorations.kPrimaryButtonLargeStyle,
            icon: const Icon(Icons.add_road, color: Colors.white),
            label: Text(
              'إنشاء رحلة لهذه المجموعة',
              style: NavigoTextStyles.button,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.message,
    this.showLoader = false,
  });

  final IconData icon;
  final String message;
  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(NavigoSizes.cardPadding),
        decoration: NavigoDecorations.kCardDecoration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: NavigoDecorations.iconCircleDecoration(
                NavigoColors.primaryOrange,
              ),
              child: Icon(icon, color: NavigoColors.primaryOrange),
            ),
            const SizedBox(height: 12),
            if (showLoader) ...[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              message,
              style: NavigoTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _detailRow(IconData icon, String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: NavigoColors.accentGreen),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          '$label: $value',
          style: NavigoTextStyles.bodySmall.copyWith(
            color: NavigoColors.textDark,
          ),
        ),
      ),
    ],
  );
}

String _routeLabel(WaitingTripGroup group) {
  final label = group.lineLabel.trim();
  if (label.isNotEmpty) return label;
  return group.routeId;
}

String _formatDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}

String _formatTime(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
