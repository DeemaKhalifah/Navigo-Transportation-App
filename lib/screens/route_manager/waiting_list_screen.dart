import 'package:flutter/material.dart';

import '../../localization/localization_x.dart';
import '../../models/waiting_trip_request.dart';
import '../../services/route_manager_route_id.dart';
import '../../services/waiting_trip_request_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_message.dart';
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
  final Set<String> _creatingGroupIds = <String>{};

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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _makeTrip(WaitingTripGroup group) async {
    if (_creatingGroupIds.contains(group.groupId)) return;

    setState(() => _creatingGroupIds.add(group.groupId));
    try {
      await _service.makeTripForGroup(group);
      if (!mounted) return;
      AppMessage.showSuccess(context, context.texts.t('waitingTripMade'));
    } catch (e) {
      if (!mounted) return;
      AppMessage.showError(context, _errorText(e));
    } finally {
      if (mounted) {
        setState(() => _creatingGroupIds.remove(group.groupId));
      }
    }
  }

  String _errorText(Object error) {
    if (error is WaitingTripRequestException) {
      return context.texts.t(error.messageKey);
    }
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    return raw.isEmpty ? context.texts.t('failedToLoadNotifications') : raw;
  }

  @override
  Widget build(BuildContext context) {
    final routeId = _routeId;

    return Scaffold(
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
                  : routeId == null || routeId.trim().isEmpty
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
                              date: _formatDate(group.departureAt),
                              time: _formatTime(group.departureAt),
                              isCreating: _creatingGroupIds.contains(
                                group.groupId,
                              ),
                              onMakeTrip: () => _makeTrip(group),
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
    required this.date,
    required this.time,
    required this.isCreating,
    required this.onMakeTrip,
  });

  final WaitingTripGroup group;
  final String date;
  final String time;
  final bool isCreating;
  final VoidCallback onMakeTrip;

  @override
  Widget build(BuildContext context) {
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
                  Icons.groups_2_outlined,
                  color: NavigoColors.primaryOrange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  group.lineLabel.isEmpty ? group.routeId : group.lineLabel,
                  style: NavigoTextStyles.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(_promptText(context), style: NavigoTextStyles.bodyMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: NavigoSizes.itemGap - 4,
            runSpacing: NavigoSizes.itemGap - 4,
            children: [
              _chip(Icons.calendar_today_outlined, date),
              _chip(Icons.access_time, time),
              _chip(
                Icons.event_seat_outlined,
                '${group.requestedSeatCount} ${context.texts.t('numberOfSeats')}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: NavigoSizes.buttonHeight,
            child: ElevatedButton.icon(
              onPressed: isCreating ? null : onMakeTrip,
              style: NavigoDecorations.kPrimaryButtonLargeStyle,
              icon: isCreating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_road, color: Colors.white),
              label: Text(
                context.texts.t('makeTrip'),
                style: NavigoTextStyles.button,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _promptText(BuildContext context) {
    return context.texts
        .t('waitingListManagerPrompt')
        .replaceAll('{passengers}', group.passengerCount.toString())
        .replaceAll('{date}', date)
        .replaceAll('{time}', time);
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: NavigoDecorations.surfaceDecoration(
        color: NavigoColors.inputFill,
        radius: 999,
        bordered: false,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: NavigoColors.accentGreen),
          const SizedBox(width: 5),
          Text(text, style: NavigoTextStyles.bodySmall),
        ],
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
