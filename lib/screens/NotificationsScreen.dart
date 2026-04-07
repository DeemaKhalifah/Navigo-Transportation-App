import 'package:flutter/material.dart';
import 'package:navigo/theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final TextEditingController searchController = TextEditingController();

  // Static placeholder notifications with read status
  final List<Map<String, dynamic>> allNotifications = [
    {
      'from': 'System',
      'date': '28 Mar',
      'title': 'Schedule Updated',
      'message':
          'The bus schedule for line Birzeit–Ramallah has been updated. Please check the new timings.',
      'isRead': false,
    },
    {
      'from': 'Lara Shaltal',
      'date': '10 Mar',
      'title': 'New Report Submitted',
      'message':
          'A passenger has submitted a new report regarding bus overcrowding on the morning trip.',
      'isRead': false,
    },
    {
      'from': 'System',
      'date': '5 Mar',
      'title': 'Driver Assigned',
      'message':
          'Ahmad Khaled has been automatically assigned to the 08:00 bus trip from Birzeit.',
      'isRead': true,
    },
    {
      'from': 'Omar Saleh',
      'date': '28 Jan',
      'title': 'Trip Delay Reported',
      'message':
          'Passenger reported a delay of more than 30 minutes on the afternoon trip.',
      'isRead': true,
    },
  ];

  List<Map<String, dynamic>> get filteredNotifications {
    final query = searchController.text.toLowerCase();
    return allNotifications.where((n) {
      return query.isEmpty ||
          n['from'].toLowerCase().contains(query) ||
          n['title'].toLowerCase().contains(query) ||
          n['message'].toLowerCase().contains(query) ||
          n['date'].toLowerCase().contains(query);
    }).toList();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _showNotificationDetail(int index) {
    setState(() {
      allNotifications[index]['isRead'] = true;
    });
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final n = allNotifications[index];
        return Container(
          decoration: const BoxDecoration(
            color: NavigoColors.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(NavigoSizes.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: NavigoColors.accentGreen.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              /// Title
              Text(n['title'], style: NavigoTextStyles.titleSmall),
              const SizedBox(height: 12),

              /// Message
              Text(n['message'], style: NavigoTextStyles.bodyMedium),
              const SizedBox(height: 16),

              /// From
              Row(
                children: [
                  Text('From: ', style: NavigoTextStyles.bodySmall),
                  Text(
                    n['from'],
                    style: NavigoTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              /// Date
              Row(
                children: [
                  Text('Date: ', style: NavigoTextStyles.bodySmall),
                  Text(
                    n['date'],
                    style: NavigoTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              /// Close button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: NavigoDecorations.kPrimaryButtonLargeStyle,
                  child: const Text('Close', style: NavigoTextStyles.button),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifications = filteredNotifications;

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,

      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// TOP BAR
            NavigoDecorations.topBar(
              onBack: () => Navigator.pop(context),
              context: context,
            ),

            /// TITLE
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NavigoSizes.screenPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notifications', style: NavigoTextStyles.titleLarge),
                  const SizedBox(height: 4),
                  Text('All notifications', style: NavigoTextStyles.bodySmall),
                ],
              ),
            ),

            const SizedBox(height: NavigoSizes.sectionGap),

            /// SEARCH BOX
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NavigoSizes.screenPadding,
              ),
              child: TextField(
                controller: searchController,
                style: NavigoTextStyles.fieldText,
                decoration: NavigoDecorations.kInputDecoration.copyWith(
                  hintText: 'Search notifications...',
                  filled: true,
                  fillColor: NavigoColors.surfaceWhite,
                  prefixIcon: const Icon(
                    Icons.search,
                    color: NavigoColors.accentGreen,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

            const SizedBox(height: NavigoSizes.sectionGap),

            /// NOTIFICATIONS LIST — Expanded so it fills remaining space
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NavigoSizes.screenPadding,
                ),
                child: notifications.isEmpty
                    ? Center(
                        child: Text(
                          'No notifications found',
                          style: NavigoTextStyles.bodySmall,
                        ),
                      )
                    : ListView.builder(
                        itemCount: notifications.length,
                        itemBuilder: (context, index) {
                          final n = notifications[index];
                          final isRead = n['isRead'] as bool;
                          final actualIndex = allNotifications.indexOf(n);

                          return GestureDetector(
                            onTap: () => _showNotificationDetail(actualIndex),
                            child: Container(
                              margin: const EdgeInsets.only(
                                bottom: NavigoSizes.itemGap,
                              ),
                              padding: const EdgeInsets.all(
                                NavigoSizes.cardPadding,
                              ),
                              decoration: NavigoDecorations.kCardDecoration,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  /// ICON CIRCLE
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration:
                                        NavigoDecorations.iconCircleDecoration(
                                          NavigoColors.accentGreen.withOpacity(
                                            0.12,
                                          ),
                                        ),
                                    child: const Icon(
                                      Icons.notifications_rounded,
                                      color: NavigoColors.accentGreen,
                                      size: 22,
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  /// NOTIFICATION CONTENT
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          n['title'],
                                          style: NavigoTextStyles.titleSmall
                                              .copyWith(
                                                fontWeight: !isRead
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          n['message'],
                                          style: NavigoTextStyles.bodyMedium
                                              .copyWith(
                                                fontWeight: !isRead
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'From: ${n['from']}',
                                          style: NavigoTextStyles.bodySmall
                                              .copyWith(
                                                fontSize: 12,
                                                fontWeight: !isRead
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  /// DATE CHIP
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      NavigoDecorations.statusChip(
                                        label: n['date'],
                                        color: NavigoColors.accentGreen,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),

            /// MARK ALL READ BUTTON — pinned at bottom
            Padding(
              padding: const EdgeInsets.all(NavigoSizes.screenPadding),
              child: SizedBox(
                width: double.infinity,
                height: NavigoSizes.buttonHeight,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      for (var notification in allNotifications) {
                        notification['isRead'] = true;
                      }
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('All notifications marked as read'),
                      ),
                    );
                  },
                  style: NavigoDecorations.kPrimaryButtonLargeStyle,
                  child: const Text(
                    'Mark all as read',
                    style: NavigoTextStyles.button,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
