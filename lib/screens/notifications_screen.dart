import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  static const String _noNotificationsFound = "No notifications found";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: NavigoDecorations.kInputDecoration.copyWith(
                  hintText: "Search notifications...",
                  prefixIcon: const Icon(Icons.search, color: NavigoColors.accentGreen),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: user == null
                  ? const Center(child: Text("No notifications found"))
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .collection('notifications')
                          .orderBy('timestamp', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.notifications_off_outlined,
                                    size: 48, color: NavigoColors.textMuted),
                                const SizedBox(height: 12),
                                const Text(_noNotificationsFound,
                                    style: NavigoTextStyles.bodySmall),
                              ],
                            ),
                          );
                        }

                        final docs = snapshot.data!.docs.where((doc) {
                          if (_searchQuery.isEmpty) return true;
                          final data = doc.data() as Map<String, dynamic>;
                          final title = (data['title'] ?? '').toString().toLowerCase();
                          final body = (data['body'] ?? '').toString().toLowerCase();
                          return title.contains(_searchQuery.toLowerCase()) ||
                              body.contains(_searchQuery.toLowerCase());
                        }).toList();

                        if (docs.isEmpty) {
                          return Center(
                            child: const Text(_noNotificationsFound,
                                style: NavigoTextStyles.bodySmall),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final data = docs[index].data() as Map<String, dynamic>;
                            return _buildNotificationCard(context, data, docs[index].reference);
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: NavigoSizes.buttonHeight,
                child: ElevatedButton(
                  onPressed: () => _markAllAsRead(context),
                  style: NavigoDecorations.kPrimaryButtonLargeStyle,
                  child: const Text("Mark all as read", style: NavigoTextStyles.button),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    Map<String, dynamic> data,
    DocumentReference ref,
  ) {
    final title = data['title']?.toString() ?? '';
    final body = data['body']?.toString() ?? '';
    final from = data['from']?.toString() ?? '';
    final isRead = data['isRead'] == true;
    final timestamp = data['timestamp'] as Timestamp?;
    final formattedDate = timestamp != null
        ? '${timestamp.toDate().day}/${timestamp.toDate().month}/${timestamp.toDate().year}'
        : '';

    return GestureDetector(
      onTap: () {
        ref.update({'isRead': true});
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
                if (from.isNotEmpty)
                  Text('From: $from', style: NavigoTextStyles.bodySmall),
                if (formattedDate.isNotEmpty)
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
                color: isRead ? NavigoColors.textMuted : NavigoColors.primaryOrange,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: NavigoTextStyles.titleSmall.copyWith(fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(body,
                      style: NavigoTextStyles.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (formattedDate.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(formattedDate, style: NavigoTextStyles.label),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _markAllAsRead(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final batch = FirebaseFirestore.instance.batch();
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();

    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("All notifications marked as read")),
    );
  }
}
