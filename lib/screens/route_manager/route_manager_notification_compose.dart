import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/notification_service.dart';
import '../../services/route_manager_route_id.dart';
import '../../theme/app_theme.dart';

class RouteManagerNotificationCompose extends StatefulWidget {
  const RouteManagerNotificationCompose({super.key});

  @override
  State<RouteManagerNotificationCompose> createState() =>
      _RouteManagerNotificationComposeState();
}

class _DriverRecipient {
  const _DriverRecipient({
    required this.driverDocId,
    required this.userId,
    required this.name,
    required this.status,
  });

  final String driverDocId;
  final String userId;
  final String name;
  final String status;
}

class _RouteManagerNotificationComposeState
    extends State<RouteManagerNotificationCompose> {
  final TextEditingController _messageController = TextEditingController();
  final NotificationService _notificationService = NotificationService();
  final Set<String> _selectedUserIds = {};

  String? _routeId;
  String? _loadError;
  bool _loadingRoute = true;
  bool _sendToAll = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRoute());
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadRoute() async {
    try {
      final routeId = await resolveManagedRouteId();
      if (!mounted) return;

      setState(() {
        _routeId = routeId;
        _loadError = routeId == null || routeId.trim().isEmpty
            ? 'No route is linked to this account.'
            : null;
        _loadingRoute = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loadingRoute = false;
      });
    }
  }

  Stream<List<_DriverRecipient>> _watchRouteDrivers(String routeId) {
    return FirebaseFirestore.instance
        .collection('drivers')
        .where('routeId', isEqualTo: routeId)
        .snapshots()
        .asyncMap(_buildDriverRecipients);
  }

  Future<List<_DriverRecipient>> _buildDriverRecipients(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final fs = FirebaseFirestore.instance;
    final userRefs = <String, DocumentReference<Map<String, dynamic>>>{};

    for (final doc in snapshot.docs) {
      final userId = (doc.data()['userId'] ?? doc.id).toString().trim();
      if (userId.isNotEmpty) {
        userRefs[userId] = fs.collection('users').doc(userId);
      }
    }

    final userSnaps = userRefs.isEmpty
        ? <DocumentSnapshot<Map<String, dynamic>>>[]
        : await Future.wait(userRefs.values.map((ref) => ref.get()));
    final usersById = {
      for (final snap in userSnaps) snap.id: snap.data(),
    };

    final drivers = <_DriverRecipient>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final userId = (data['userId'] ?? doc.id).toString().trim();
      if (userId.isEmpty) continue;

      final user = usersById[userId];
      final firstName = (user?['firstName'] ?? data['firstName'] ?? '')
          .toString()
          .trim();
      final lastName = (user?['lastName'] ?? data['lastName'] ?? '')
          .toString()
          .trim();
      final fullName = '$firstName $lastName'.trim();
      final fallbackName = (data['fullName'] ?? '').toString().trim();
      final prefixLength = doc.id.length < 6 ? doc.id.length : 6;
      final name = fullName.isNotEmpty
          ? fullName
          : fallbackName.isNotEmpty
          ? fallbackName
          : 'Driver ${doc.id.substring(0, prefixLength)}';

      drivers.add(
        _DriverRecipient(
          driverDocId: doc.id,
          userId: userId,
          name: name,
          status: (data['status'] ?? 'offline').toString(),
        ),
      );
    }

    drivers.sort((a, b) => a.name.compareTo(b.name));
    return drivers;
  }

  Future<void> _send(List<_DriverRecipient> drivers) async {
    final message = _messageController.text.trim();
    final recipients = _sendToAll
        ? drivers
        : drivers.where((d) => _selectedUserIds.contains(d.userId)).toList();

    if (message.isEmpty) {
      _showSnack('Write a notification message first.');
      return;
    }
    if (recipients.isEmpty) {
      _showSnack('Choose at least one driver.');
      return;
    }

    final routeId = _routeId;
    if (routeId == null || routeId.trim().isEmpty) {
      _showSnack('No route is linked to this account.');
      return;
    }

    setState(() => _sending = true);
    try {
      await _notificationService.createRouteManagerDriverNotifications(
        routeId: routeId,
        senderId: FirebaseAuth.instance.currentUser?.uid ?? '',
        message: message,
        driverUserIds: recipients.map((d) => d.userId).toList(),
        driverDocIdsByUserId: {
          for (final d in recipients) d.userId: d.driverDocId,
        },
        receiverScope: _sendToAll ? 'all' : 'specific',
      );

      if (!mounted) return;
      _messageController.clear();
      setState(() => _selectedUserIds.clear());
      _showSnack('Notification sent to ${recipients.length} driver(s).');
    } on ArgumentError catch (e) {
      if (mounted) _showSnack(e.message.toString());
    } catch (e) {
      if (mounted) _showSnack('Could not send notification: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeId = _routeId;

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar1(onBack: () => Navigator.pop(context)),
            NavigoDecorations.pageTitle(
              title: 'Send notification',
              subtitle: 'Message drivers on your route',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loadingRoute
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                  ? _buildEmptyState(_loadError!)
                  : StreamBuilder<List<_DriverRecipient>>(
                      stream: _watchRouteDrivers(routeId!),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return _buildEmptyState(
                            'Failed to load route drivers.',
                          );
                        }

                        final drivers = snapshot.data ?? [];
                        return _buildComposer(drivers);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: NavigoTextStyles.bodyMedium,
        ),
      ),
    );
  }

  Widget _buildComposer(List<_DriverRecipient> drivers) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _messageController,
            minLines: 5,
            maxLines: 8,
            textInputAction: TextInputAction.newline,
            style: NavigoTextStyles.fieldText,
            decoration: NavigoDecorations.kInputDecoration.copyWith(
              hintText: 'Write the notification message...',
              filled: true,
              fillColor: NavigoColors.surfaceWhite,
              alignLabelWithHint: true,
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 82),
                child: Icon(Icons.message_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Receivers', style: NavigoTextStyles.titleSmall),
          const SizedBox(height: 10),
          Row(
            children: [
              NavigoDecorations.selectorChip(
                label: 'All drivers',
                selected: _sendToAll,
                onTap: () => setState(() => _sendToAll = true),
              ),
              const SizedBox(width: 8),
              NavigoDecorations.selectorChip(
                label: 'Specific',
                selected: !_sendToAll,
                onTap: () => setState(() => _sendToAll = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (drivers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: NavigoDecorations.surfaceDecoration(),
              child: Text(
                'No drivers are assigned to this route.',
                style: NavigoTextStyles.bodySmall,
              ),
            )
          else
            ...drivers.map(_buildDriverTile),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: NavigoSizes.buttonHeight,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : () => _send(drivers),
              style: NavigoDecorations.kPrimaryButtonLargeStyle,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _sending ? 'Sending...' : 'Send notification',
                style: NavigoTextStyles.button,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverTile(_DriverRecipient driver) {
    final selected = _sendToAll || _selectedUserIds.contains(driver.userId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: NavigoDecorations.kCardDecoration.copyWith(
        color: selected ? NavigoColors.lightorange : NavigoColors.surfaceWhite,
      ),
      child: CheckboxListTile(
        value: selected,
        enabled: !_sendToAll,
        activeColor: NavigoColors.primaryOrange,
        onChanged: (value) {
          setState(() {
            if (value == true) {
              _selectedUserIds.add(driver.userId);
            } else {
              _selectedUserIds.remove(driver.userId);
            }
          });
        },
        title: Text(
          driver.name,
          style: NavigoTextStyles.titleSmall.copyWith(fontSize: 15),
        ),
        subtitle: Text(
          'Status: ${driver.status}',
          style: NavigoTextStyles.bodySmall,
        ),
        secondary: CircleAvatar(
          backgroundColor: NavigoColors.accentGreen.withOpacity(0.14),
          child: const Icon(
            Icons.directions_bus_filled_outlined,
            color: NavigoColors.accentGreen,
            size: 20,
          ),
        ),
      ),
    );
  }
}
