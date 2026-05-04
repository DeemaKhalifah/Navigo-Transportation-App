import 'package:flutter/material.dart';
import '../../localization/localization_x.dart';
import '../../services/support_report_service.dart';
import '../../theme/app_theme.dart';
import 'manager_profile.dart';
import 'reports.dart';
import 'route_schedule.dart';
import 'assign_driver.dart';

class RouteManagerNavBar extends StatefulWidget {
  final int currentIndex;

  const RouteManagerNavBar({super.key, required this.currentIndex});

  @override
  State<RouteManagerNavBar> createState() => _RouteManagerNavBarState();
}

class _RouteManagerNavBarState extends State<RouteManagerNavBar> {
  final SupportReportService _reportService = SupportReportService();

  void _onItemTapped(BuildContext context, int index) {
    if (index == widget.currentIndex) return;

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
              _buildItem(context, 0, Icons.schedule, context.texts.t('schedule')),
              _buildItem(context, 1, Icons.assignment, context.texts.t('assign')),
              _buildReportsItem(context),
              _buildItem(context, 3, Icons.person, context.texts.t('profile')),
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

  Widget _buildReportsItem(BuildContext context) {
    return StreamBuilder<int>(
      stream: _reportService.watchUnreadCountForCurrentRouteManager(),
      initialData: 0,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final icon = count > 0
            ? _badgeIcon(Icons.bar_chart, count)
            : const Icon(Icons.bar_chart);

        final bool isActive = widget.currentIndex == 2;
        return GestureDetector(
          onTap: () => _onItemTapped(context, 2),
          child: NavigoDecorations.navItem(
            icon: Icons.bar_chart,
            iconWidget: icon,
            label: context.texts.t('reports'),
            isActive: isActive,
          ),
        );
      },
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
