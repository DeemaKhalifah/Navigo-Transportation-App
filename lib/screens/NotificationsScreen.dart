import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:navigo/screens/route_manager/RouteSchedule.dart';
import 'package:navigo/theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final TextEditingController searchController = TextEditingController();

  // Static placeholder notifications — same pattern as allReports
  final List<Map<String, String>> allNotifications = [
    {
      'from': 'System',
      'date': '28 Mar',
      'type': 'system',
      'title': 'Schedule Updated',
      'message':
          'The bus schedule for line Birzeit–Ramallah has been updated. Please check the new timings.',
    },
    {
      'from': 'Lara Shaltal',
      'date': '10 Mar',
      'type': 'user',
      'title': 'New Report Submitted',
      'message':
          'A passenger has submitted a new report regarding bus overcrowding on the morning trip.',
    },
    {
      'from': 'System',
      'date': '5 Mar',
      'type': 'system',
      'title': 'Driver Assigned',
      'message':
          'Ahmad Khaled has been automatically assigned to the 08:00 bus trip from Birzeit.',
    },
    {
      'from': 'Omar Saleh',
      'date': '28 Jan',
      'type': 'user',
      'title': 'Trip Delay Reported',
      'message':
          'Passenger reported a delay of more than 30 minutes on the afternoon trip.',
    },
  ];

  String _selectedFilter = 'all'; // 'all' | 'user' | 'system'

  List<Map<String, String>> get filteredNotifications {
    final query = searchController.text.toLowerCase();
    return allNotifications.where((n) {
      final matchesSearch =
          query.isEmpty ||
          n['from']!.toLowerCase().contains(query) ||
          n['title']!.toLowerCase().contains(query) ||
          n['message']!.toLowerCase().contains(query) ||
          n['date']!.toLowerCase().contains(query);
      final matchesFilter =
          _selectedFilter == 'all' || n['type'] == _selectedFilter;
      return matchesSearch && matchesFilter;
    }).toList();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Widget _filterChip(String type, String label) {
    final selected = _selectedFilter == type;
    return NavigoDecorations.selectorChip(
      label: label,
      selected: selected,
      onTap: () => setState(() => _selectedFilter = type),
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
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RouteSchedule()),
              ),
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
                  Text(
                    'All user and system notifications',
                    style: NavigoTextStyles.bodySmall,
                  ),
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

            const SizedBox(height: 12),

            /// FILTER CHIPS
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NavigoSizes.screenPadding,
              ),
              child: Row(
                children: [
                  _filterChip('all', 'All'),
                  const SizedBox(width: 8),
                  _filterChip('user', 'User'),
                  const SizedBox(width: 8),
                  _filterChip('system', 'System'),
                ],
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
                          final isSystem = n['type'] == 'system';

                          return Container(
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
                                        isSystem
                                            ? NavigoColors.accentGreen
                                                  .withOpacity(0.12)
                                            : NavigoColors.primaryOrange
                                                  .withOpacity(0.12),
                                      ),
                                  child: Icon(
                                    isSystem
                                        ? Icons.notifications_rounded
                                        : Icons.person_rounded,
                                    color: isSystem
                                        ? NavigoColors.accentGreen
                                        : NavigoColors.primaryOrange,
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
                                        n['title']!,
                                        style: NavigoTextStyles.titleSmall,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        n['message']!,
                                        style: NavigoTextStyles.bodyMedium,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'From: ${n['from']}',
                                        style: NavigoTextStyles.bodySmall
                                            .copyWith(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 8),

                                /// DATE + TYPE CHIP
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    NavigoDecorations.statusChip(
                                      label: n['date']!,
                                      color: NavigoColors.accentGreen,
                                    ),
                                    const SizedBox(height: 6),
                                    NavigoDecorations.statusChip(
                                      label: isSystem ? 'System' : 'User',
                                      color: isSystem
                                          ? NavigoColors.accentGreen
                                          : NavigoColors.primaryOrange,
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

            /// MARK ALL READ BUTTON — pinned at bottom
            Padding(
              padding: const EdgeInsets.all(NavigoSizes.screenPadding),
              child: SizedBox(
                width: double.infinity,
                height: NavigoSizes.buttonHeight,
                child: ElevatedButton(
                  onPressed: () {
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
