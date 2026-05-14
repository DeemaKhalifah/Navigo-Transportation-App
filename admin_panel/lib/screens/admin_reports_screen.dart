import 'package:flutter/material.dart';

import '../models/admin_dashboard_model.dart';
import '../services/admin_dashboard_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_account_dialog.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final AdminDashboardService _service = AdminDashboardService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: Row(
        children: [
          _ReportsSidebar(onDashboard: () => Navigator.pop(context)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 24, 16),
              child: Container(
                decoration: _cardDecoration(radius: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reports Sent To Admin',
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Reports sent by route managers from supportReports',
                                  style: NavigoTextStyles.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: StreamBuilder<List<AdminReportItem>>(
                        stream: _service.adminReportsStream(),
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
                                'Error loading reports: ${snapshot.error}',
                              ),
                            );
                          }

                          final reports = snapshot.data ?? [];

                          if (reports.isEmpty) {
                            return const Center(
                              child: Text(
                                'No reports sent to admin yet',
                                style: NavigoTextStyles.bodyMedium,
                              ),
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.all(24),
                            itemCount: reports.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final report = reports[index];

                              return _ReportTile(
                                report: report,
                                onTap: () => _showReportDetails(report),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDetails(AdminReportItem report) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 56,
            vertical: 40,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.purple.withValues(alpha: 0.12),
                          child: const Icon(
                            Icons.description_rounded,
                            color: Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Report Details',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _DetailSection(
                      title: 'Report Information',
                      children: [
                        _DetailRow(label: 'Report ID', value: report.id),
                        _DetailRow(
                          label: 'Status',
                          value: _formatStatus(report.status),
                        ),
                        _DetailRow(
                          label: 'Created At',
                          value: _formatDate(report.createdAt),
                        ),
                        _DetailRow(
                          label: 'Sent To Admin At',
                          value: _formatDate(report.sentToAdminAt),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: 'Sender And Route',
                      children: [
                        _DetailRow(label: 'Sender', value: report.senderName),
                        _DetailRow(
                          label: 'Sender Role',
                          value: report.senderRole,
                        ),
                        _DetailRow(label: 'Route', value: report.routeLabel),
                        if (report.routeId.isNotEmpty)
                          _DetailRow(label: 'Route ID', value: report.routeId),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: 'Message',
                      children: [
                        SelectableText(
                          report.message,
                          style: NavigoTextStyles.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: NavigoColors.primaryOrange,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReportsSidebar extends StatelessWidget {
  final VoidCallback onDashboard;

  const _ReportsSidebar({required this.onDashboard});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: NavigoColors.primaryOrange,
                child: Icon(Icons.directions_bus, color: Colors.white),
              ),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Navigo Admin', style: NavigoTextStyles.titleSmall),
                  Text(
                    'System Control Panel',
                    style: NavigoTextStyles.bodySmall,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 35),
          _SidebarItem(
            icon: Icons.dashboard_rounded,
            title: 'Dashboard',
            onTap: onDashboard,
          ),
          const _SidebarItem(icon: Icons.person_rounded, title: 'Drivers'),
          const _SidebarItem(icon: Icons.route_rounded, title: 'Routes'),
          const _SidebarItem(
            icon: Icons.directions_bus_rounded,
            title: 'Trips',
          ),
          const _SidebarItem(
            icon: Icons.people_alt_rounded,
            title: 'Passengers',
          ),
          const _SidebarItem(
            icon: Icons.bar_chart_rounded,
            title: 'Reports',
            selected: true,
          ),
          const Spacer(),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => showAdminAccountDialog(context),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: NavigoColors.backgroundAlt,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: NavigoColors.borderLight),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: NavigoColors.primaryOrange,
                      child: Text('A', style: TextStyle(color: Colors.white)),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Admin',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Change password',
                            style: NavigoTextStyles.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback? onTap;

  const _SidebarItem({
    required this.icon,
    required this.title,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected
            ? NavigoColors.primaryOrange.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: selected ? NavigoColors.primaryOrange : NavigoColors.textGray,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected
                ? NavigoColors.primaryOrange
                : NavigoColors.textDark,
          ),
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final AdminReportItem report;
  final VoidCallback onTap;

  const _ReportTile({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NavigoColors.borderLight),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: Colors.purple.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.description_rounded,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.senderName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _StatusChip(label: _formatStatus(report.status)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(report.message, style: NavigoTextStyles.bodyMedium),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        _ReportMeta(
                          icon: Icons.badge_rounded,
                          text: report.senderRole,
                        ),
                        _ReportMeta(
                          icon: Icons.route_rounded,
                          text: report.routeLabel,
                        ),
                        _ReportMeta(
                          icon: Icons.schedule_rounded,
                          text: _formatDate(
                            report.sentToAdminAt ?? report.createdAt,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.open_in_new_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: SelectableText(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NavigoColors.backgroundAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NavigoColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: NavigoTextStyles.titleSmall),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _ReportMeta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ReportMeta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: NavigoColors.textGray),
        const SizedBox(width: 5),
        Text(text, style: NavigoTextStyles.bodySmall),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;

  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.purple,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

String _formatStatus(String status) {
  return status
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _formatDate(DateTime? date) {
  if (date == null) return 'No date';

  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');

  return '${date.year}-$month-$day $hour:$minute';
}

BoxDecoration _cardDecoration({double radius = 18}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: NavigoColors.borderLight),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}
