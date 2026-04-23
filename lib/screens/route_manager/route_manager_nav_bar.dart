import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'manager_profile.dart';
import 'reports.dart';
import 'route_schedule.dart';
import 'assign_driver.dart';

class RouteManagerNavBar extends StatelessWidget {
  final int currentIndex;

  const RouteManagerNavBar({super.key, required this.currentIndex});

  void _onItemTapped(BuildContext context, int index) {
    if (index == currentIndex) return;

    Widget screen;

    switch (index) {
      case 0:
        screen = const RouteSchedule();
        break;
      case 1:
        screen = const AssignDriver();
        break;
      case 2:
        screen = const Reports();
        break;
      case 3:
        screen = const ManagerProfile();
        break;
      default:
        screen = const RouteSchedule();
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
              _buildItem(context, 0, Icons.schedule, "Schedule"),
              _buildItem(context, 1, Icons.assignment, "Assign"),
              _buildItem(context, 2, Icons.bar_chart, "Reports"),
              _buildItem(context, 3, Icons.person, "Profile"),
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
