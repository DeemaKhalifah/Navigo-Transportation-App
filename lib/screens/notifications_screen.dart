import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../localization/localization_x.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'route_manager/add_schedule_slot_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.initialNotificationId,
    this.initialTitle,
    this.initialBody,
  });

  final String? initialNotificationId;
  final String? initialTitle;
  final String? initialBody;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final NotificationService _notificationService = NotificationService();

  String _searchQuery = '';
  bool _initialNotificationShown = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<NotificationModel> _filterNotifications(
    List<NotificationModel> notifications,
  ) {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) return notifications;

    return notifications.where((notification) {
      return notification.title.toLowerCase().contains(query) ||
          notification.message.toLowerCase().contains(query) ||
          notification.type.toLowerCase().contains(query);
    }).toList();
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _localizedTitle(NotificationModel notification) {
    final key = notification.titleKey.trim();
    if (key.isNotEmpty) return context.texts.t(key);
    return notification.title;
  }

  String _localizedMessage(NotificationModel notification) {
    final key = notification.messageKey.trim();
    if (key.isNotEmpty) return context.texts.t(key);
    return notification.message;
  }

  Future<void> _showNotificationMessage(NotificationModel notification) async {
    await _notificationService.markAsRead(notification.notificationId);

    if (!mounted) return;

    await _showNotificationDialog(
      notification: notification,
      title: _localizedTitle(notification),
      body: _localizedMessage(notification),
      dateText: _formatDate(notification.timestamp),
    );
  }

  Future<void> _showInitialNotificationIfNeeded(
    List<NotificationModel> notifications,
  ) async {
    if (_initialNotificationShown) return;
    _initialNotificationShown = true;

    final initialId = widget.initialNotificationId?.trim() ?? '';
    final initialTitle = widget.initialTitle?.trim() ?? '';
    final initialBody = widget.initialBody?.trim() ?? '';

    if (initialId.isNotEmpty) {
      for (final notification in notifications) {
        if (notification.notificationId == initialId) {
          await _showNotificationMessage(notification);
          return;
        }
      }

      await _notificationService.markAsRead(initialId);
    }

    if (!mounted || (initialTitle.isEmpty && initialBody.isEmpty)) return;

    await _showNotificationDialog(title: initialTitle, body: initialBody);
  }

  Future<void> _showNotificationDialog({
    NotificationModel? notification,
    required String title,
    required String body,
    String? dateText,
  }) async {
    if (!mounted) return;

    final safeTitle = title.trim().isEmpty
        ? context.texts.t('notifications')
        : title.trim();
    final safeBody = body.trim();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(safeTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (safeBody.isNotEmpty)
                Text(safeBody, style: NavigoTextStyles.bodyMedium),
              if (dateText != null && dateText.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  dateText.trim(),
                  style: NavigoTextStyles.label.copyWith(
                    color: NavigoColors.textMuted,
                  ),
                ),
              ],
              if (notification?.type == 'waiting_trip_manager_request') ...[
                const SizedBox(height: 14),
                _dialogDetail(
                  context.texts.t('date'),
                  notification?.departureAt == null
                      ? ''
                      : _formatDate(notification!.departureAt!),
                ),
                _dialogDetail(
                  context.texts.t('time'),
                  notification?.departureAt == null
                      ? ''
                      : _formatTime(notification!.departureAt!),
                ),
                _dialogDetail(
                  context.texts.t('numberOfSeats'),
                  '${notification?.requestedSeatCount ?? 0}',
                ),
              ],
            ],
          ),
          actions: [
            if (notification?.type == 'waiting_trip_manager_request' &&
                (notification?.routeId.trim().isNotEmpty ?? false))
              TextButton(
                onPressed: () {
                  final n = notification!;
                  Navigator.pop(dialogContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddScheduleSlotScreen(
                        routeId: n.routeId,
                        waitingTripGroupId: n.waitingTripGroupId,
                        initialDepartureAt: n.departureAt,
                        initialCapacity: n.requestedSeatCount,
                      ),
                    ),
                  );
                },
                child: Text(context.texts.t('createTrip')),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.texts.t('close')),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _dialogDetail(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text('$label: $value', style: NavigoTextStyles.bodySmall),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pop(context),
              context: context,
            ),

            NavigoDecorations.pageTitle(
              title: context.texts.t('notifications'),
              subtitle: context.texts.t('allNotifications'),
            ),

            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                decoration: NavigoDecorations.kInputDecoration.copyWith(
                  hintText: context.texts.t('searchNotifications'),
                  filled: true,
                  fillColor: NavigoColors.surfaceWhite,
                  prefixIcon: const Icon(
                    Icons.search,
                    color: NavigoColors.accentGreen,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: user == null
                  ? Center(
                      child: Text(
                        context.texts.t('noNotificationsFound'),
                        style: NavigoTextStyles.bodySmall,
                      ),
                    )
                  : StreamBuilder<List<NotificationModel>>(
                      stream: _notificationService.watchUserNotifications(
                        user.uid,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              context.texts.t('failedToLoadNotifications'),
                              style: NavigoTextStyles.bodySmall,
                            ),
                          );
                        }

                        final notifications = _filterNotifications(
                          snapshot.data ?? [],
                        );
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _showInitialNotificationIfNeeded(snapshot.data ?? []);
                        });

                        if (notifications.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.notifications_off_outlined,
                                  size: 48,
                                  color: NavigoColors.textMuted,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  context.texts.t('noNotificationsFound'),
                                  style: NavigoTextStyles.bodySmall,
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: notifications.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _buildNotificationCard(
                              context,
                              notifications[index],
                            );
                          },
                        );
                      },
                    ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    NotificationModel notification,
  ) {
    final title = _localizedTitle(notification);
    final body = _localizedMessage(notification);
    final isRead = notification.isRead;
    final formattedDate = _formatDate(notification.timestamp);

    return GestureDetector(
      onTap: () async {
        await _showNotificationMessage(notification);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: NavigoDecorations.kCardDecoration.copyWith(
          color: isRead ? NavigoColors.surfaceWhite : NavigoColors.lightorange,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: NavigoDecorations.iconCircleDecoration(
                isRead ? NavigoColors.textMuted : NavigoColors.primaryOrange,
              ),
              child: Icon(
                isRead ? Icons.mark_email_read : Icons.notifications_active,
                color: isRead
                    ? NavigoColors.textMuted
                    : NavigoColors.primaryOrange,
                size: 20,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: NavigoTextStyles.titleSmall.copyWith(fontSize: 15),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    body,
                    style: NavigoTextStyles.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  Text(formattedDate, style: NavigoTextStyles.label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
