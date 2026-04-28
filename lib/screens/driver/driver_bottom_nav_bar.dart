import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/trip_driver_request_service.dart';
import '../../theme/app_theme.dart';
import '../driver/driver_profile_screen.dart';
import '../driver/driver_requests_screen.dart';
import '../driver/driver_trips_screen.dart';
import 'driver_home_screen.dart';

class DriverBottomNavBar extends StatefulWidget {
  final int currentIndex;

  const DriverBottomNavBar({super.key, required this.currentIndex});

  @override
  State<DriverBottomNavBar> createState() => _DriverBottomNavBarState();
}

class _DriverBottomNavBarState extends State<DriverBottomNavBar> {
  final TripDriverRequestService _requestService = TripDriverRequestService();

  void _onItemTapped(BuildContext context, int index) {
    if (index == widget.currentIndex) return;

    Widget screen = const DriverHomeScreen();

    switch (index) {
      case 0:
        screen = const DriverHomeScreen();
        break;
      case 1:
        screen = const DriverTripsScreen();
        break;
      case 2:
        screen = const DriverRequestsScreen();
        break;
      case 3:
        screen = const DriverProfileScreen();
        break;
      default:
        screen = const DriverHomeScreen();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driverId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Container(
      decoration: NavigoDecorations.kBottomNavDecoration,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildItem(context, 0, Icons.home_outlined, "Home"),
              _buildItem(context, 1, Icons.receipt_long_outlined, "Trips"),
              StreamBuilder<int>(
                stream: _requestService.watchPendingCountForDriver(driverId),
                initialData: 0,
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  final iconWidget = count > 0
                      ? _badgeIcon(Icons.notifications_none, count)
                      : const Icon(Icons.notifications_none);

                  return GestureDetector(
                    onTap: () => _onItemTapped(context, 2),
                    child: NavigoDecorations.navItem(
                      icon: Icons.notifications_none,
                      iconWidget: iconWidget,
                      label: "Requests",
                      isActive: widget.currentIndex == 2,
                    ),
                  );
                },
              ),
              _buildItem(context, 3, Icons.person_outline, "Profile"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    int index,
    IconData icon,
    String label,
  ) {
    final bool isActive = index == widget.currentIndex;

    return GestureDetector(
      onTap: () => _onItemTapped(context, index),
      child: NavigoDecorations.navItem(
        icon: icon,
        label: label,
        isActive: isActive,
      ),
    );
  }

  Widget _badgeIcon(IconData iconData, int count) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(iconData),
        Positioned(
          right: -8,
          top: -8,
          child: Container(
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: NavigoColors.accentRed,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Text(
              count > 99 ? '99+' : count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
