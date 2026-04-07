import 'package:flutter/material.dart';
import 'package:navigo/screens/passenger/Triphistoryscreen.dart';
import '../../theme/app_theme.dart';
import 'passengerHomeScreen.dart';
import 'ScheduleScreen.dart';
//import 'RouteDetailsScreen.dart';
import 'ProfileScreen.dart';

class PassengerBottomNavBar extends StatelessWidget {
  final int currentIndex;

  const PassengerBottomNavBar({super.key, required this.currentIndex});

  void _onItemTapped(BuildContext context, int index) {
    if (index == currentIndex) return;

    Widget screen;

    switch (index) {
      case 0:
        screen = const PassengerHomeScreen();
        break;
      case 1:
        screen = const ScheduleScreen();
        break;
      case 2:
        screen = const TripHistoryScreen();
        //screen = const RouteDetailsScreen();
        break;
      case 3:
        screen = const ProfileScreen();
        break;
      default:
        screen = const PassengerHomeScreen();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: NavigoDecorations.kBottomNavDecoration,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildItem(context, 0, Icons.home_outlined, "Home"),
              _buildItem(context, 1, Icons.directions_bus_outlined, "Schedule"),
              _buildItem(context, 2, Icons.receipt_long_outlined, "Trips"),
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
    final bool isActive = index == currentIndex;

    return GestureDetector(
      onTap: () => _onItemTapped(context, index),
      child: NavigoDecorations.navItem(
        icon: icon,
        label: label,
        isActive: isActive,
      ),
    );
  }
}
