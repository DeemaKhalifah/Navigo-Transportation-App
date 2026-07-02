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

  void _openCreateTrip() {
    final routeId = _routeId;
    if (routeId == null || routeId.trim().isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddScheduleSlotScreen(routeId: routeId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeId = _routeId;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: NavigoColors.backgroundLight,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (routeId != null && routeId.trim().isNotEmpty)
              _BottomCreateTripButton(onPressed: _openCreateTrip),
            const RouteManagerNavBar(currentIndex: 2),
          ],
        ),
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
                                  message: context.texts.t(
                                    'noWaitingListRequests',
                                  ),
                                );
                              }

                              return ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  20,
                                ),
                                itemCount: groups.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final group = groups[index];
                                  return _WaitingGroupCard(
                                    group: group,
                                    requestsStream: _service
                                        .watchRequestsForGroup(group.groupId),
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

class _WaitingGroupCard extends StatelessWidget {
  const _WaitingGroupCard({
    required this.group,
    required this.requestsStream,
  });

  final WaitingTripGroup group;
  final Stream<List<WaitingTripRequest>> requestsStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WaitingTripRequest>>(
      stream: requestsStream,
      builder: (context, snapshot) {
        final requests = snapshot.data ?? const [];

        if (requests.isEmpty) {
          return _WaitingRequestInfoCard(
            passengerName: context.texts.t('unknownUser'),
            date: _formatDate(group.departureAt),
            time: _formatTime(group.departureAt),
            seats: group.requestedSeatCount,
          );
        }

        return Column(
          children: [
            for (var i = 0; i < requests.length; i++) ...[
              _WaitingRequestInfoCard(
                passengerName: requests[i].passengerName.trim().isEmpty
                    ? context.texts.t('unknownUser')
                    : requests[i].passengerName.trim(),
                date: _formatDate(requests[i].departureAt),
                time: _formatTime(requests[i].departureAt),
                seats: requests[i].seatsRequested,
              ),
              if (i != requests.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _WaitingRequestInfoCard extends StatelessWidget {
  const _WaitingRequestInfoCard({
    required this.passengerName,
    required this.date,
    required this.time,
    required this.seats,
  });

  final String passengerName;
  final String date;
  final String time;
  final int seats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(NavigoSizes.cardPadding),
      decoration: NavigoDecorations.kCardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow(
            Icons.person_outline,
            context.texts.t('passenger'),
            passengerName,
          ),
          const SizedBox(height: 10),
          _detailRow(
            Icons.calendar_today_outlined,
            context.texts.t('date'),
            date,
          ),
          const SizedBox(height: 10),
          _detailRow(Icons.access_time, context.texts.t('time'), time),
          const SizedBox(height: 10),
          _detailRow(
            Icons.event_seat_outlined,
            context.texts.t('numberOfSeats'),
            seats.toString(),
          ),
        ],
      ),
    );
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
}

class _BottomCreateTripButton extends StatelessWidget {
  const _BottomCreateTripButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
        color: NavigoColors.backgroundLight,
        child: SizedBox(
          height: NavigoSizes.buttonHeight,
          child: ElevatedButton.icon(
            onPressed: onPressed,
            style: NavigoDecorations.kPrimaryButtonLargeStyle,
            icon: const Icon(Icons.add_road, color: Colors.white),
            label: Text(
              context.texts.t('createTrip'),
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
