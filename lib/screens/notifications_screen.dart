import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final NotificationService _notificationService = NotificationService();

  String _searchQuery = '';

  static const String _noNotificationsFound = "No notifications found";

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
              title: "Notifications",
              subtitle: "All notifications",
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
                  hintText: "Search notifications...",
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
                  ? const Center(
                      child: Text(
                        _noNotificationsFound,
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
                              "Failed to load notifications",
                              style: NavigoTextStyles.bodySmall,
                            ),
                          );
                        }

                        final notifications = _filterNotifications(
                          snapshot.data ?? [],
                        );

                        if (notifications.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.notifications_off_outlined,
                                  size: 48,
                                  color: NavigoColors.textMuted,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  _noNotificationsFound,
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
    final title = notification.title;
    final body = notification.message;
    final isRead = notification.isRead;
    final formattedDate = _formatDate(notification.timestamp);

    return GestureDetector(
      onTap: () async {
        await _notificationService.markAsRead(notification.notificationId);

        if (!context.mounted) return;

        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(body),

                const SizedBox(height: 12),

                Text('Date: $formattedDate', style: NavigoTextStyles.bodySmall),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          ),
        );
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
