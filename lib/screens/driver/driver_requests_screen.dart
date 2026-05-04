import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../localization/localization_x.dart';
import '../../models/trip_driver_request.dart';
import '../../services/trip_driver_request_service.dart';
import '../../theme/app_theme.dart';
import 'driver_bottom_nav_bar.dart';
import 'driver_home_screen.dart';

class DriverRequestsScreen extends StatefulWidget {
  const DriverRequestsScreen({super.key});

  @override
  State<DriverRequestsScreen> createState() => _DriverRequestsScreenState();
}

class _DriverRequestsScreenState extends State<DriverRequestsScreen> {
  final TripDriverRequestService _requestService = TripDriverRequestService();
  String _searchText = '';
  final Set<String> _busyIds = {};

  String? get _driverId => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final driverId = _driverId;

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const DriverBottomNavBar(currentIndex: 2),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
              ),
              context: context,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(context.texts.t('tripRequests'), style: NavigoTextStyles.titleLarge),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: NavigoDecorations.kInputDecoration.copyWith(
                  hintText: context.texts.t('searchRequests'),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: NavigoColors.accentGreen,
                  ),
                  fillColor: NavigoColors.surfaceWhite,
                ),
                onChanged: (value) => setState(() => _searchText = value),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: driverId == null || driverId.isEmpty
                  ? Center(
                      child: Text(
                        context.texts.t('signInToSeeRequests'),
                        style: NavigoTextStyles.bodySmall,
                      ),
                    )
                  : StreamBuilder<List<TripDriverRequest>>(
                      stream: _requestService.watchPendingForDriver(driverId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                '${context.texts.t('couldNotLoadRequests')}\n${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: NavigoTextStyles.bodySmall,
                              ),
                            ),
                          );
                        }

                        final all = snapshot.data ?? [];
                        final q = _searchText.trim().toLowerCase();
                        final filtered = q.isEmpty
                            ? all
                            : all.where((r) {
                                final hay = [
                                  r.lineLabel,
                                  r.startPoint,
                                  r.endPoint,
                                  r.pickupDescription,
                                  r.passengerId,
                                ].join(' ').toLowerCase();
                                return hay.contains(q);
                              }).toList();

                        if (filtered.isEmpty) {
                          return Center(
                            child: Text(
                              all.isEmpty
                                  ? context.texts.t('noPendingRequests')
                                  : context.texts.t('noRequestsMatch'),
                              style: NavigoTextStyles.bodySmall,
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _RequestCard(
                              request: filtered[index],
                              busy: _busyIds.contains(filtered[index].requestId),
                              onDecline: () => _respond(
                                filtered[index].requestId,
                                accept: false,
                              ),
                              onAccept: () => _respond(
                                filtered[index].requestId,
                                accept: true,
                              ),
                              nameFuture: _requestService.passengerDisplayName(
                                filtered[index].passengerId,
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _respond(String requestId, {required bool accept}) async {
    setState(() => _busyIds.add(requestId));
    try {
      if (accept) {
        await _requestService.acceptRequest(requestId);
      } else {
        await _requestService.declineRequest(requestId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? context.texts.t('requestAccepted') : context.texts.t('requestDeclined')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyIds.remove(requestId));
      }
    }
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.busy,
    required this.onDecline,
    required this.onAccept,
    required this.nameFuture,
  });

  final TripDriverRequest request;
  final bool busy;
  final VoidCallback onDecline;
  final VoidCallback onAccept;
  final Future<String?> nameFuture;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: NavigoDecorations.kCardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person,
                color: NavigoColors.accentGreen,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FutureBuilder<String?>(
                  future: nameFuture,
                  builder: (context, snap) {
                    final name = snap.data;
                    return Text(
                      name == null || name.isEmpty
                          ? 'Passenger ${request.passengerId.length > 6 ? request.passengerId.substring(0, 6) : request.passengerId}…'
                          : name,
                      style: NavigoTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: NavigoColors.textDark,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            request.lineLabel.isNotEmpty
                ? request.lineLabel
                : '${request.startPoint} → ${request.endPoint}',
            style: NavigoTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: NavigoColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${context.texts.t('pickup')}: ${request.pickupDescription.isEmpty ? '—' : request.pickupDescription}',
            style: NavigoTextStyles.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${context.texts.t('to')}: ${request.endPoint.isEmpty ? '—' : request.endPoint}',
            style: NavigoTextStyles.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${context.texts.t('seats')}: ${request.seatsRequested}',
            style: NavigoTextStyles.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : onDecline,
                  style: NavigoDecorations.coloredButton(NavigoColors.accentRed),
                  child: Text(context.texts.t('decline')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : onAccept,
                  style: NavigoDecorations.kPrimaryButtonLargeStyle,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.texts.t('accept')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
