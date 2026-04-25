import 'package:flutter/material.dart';

import '../../models/support_report.dart';
import '../../services/support_report_service.dart';
import '../../theme/app_theme.dart';
import 'route_manager_nav_bar.dart';
import 'route_schedule.dart';

class Reports extends StatefulWidget {
  const Reports({super.key});

  @override
  State<Reports> createState() => _ReportsState();
}

class _ReportsState extends State<Reports> {
  final TextEditingController searchController = TextEditingController();
  final SupportReportService _service = SupportReportService();

  final Set<String> selectedReportIds = {};

  String query = '';
  bool _sending = false;

  List<SupportReport> _filterReports(List<SupportReport> reports) {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) return reports;

    return reports.where((report) {
      return report.senderName.toLowerCase().contains(q) ||
          report.senderRole.toLowerCase().contains(q) ||
          report.message.toLowerCase().contains(q) ||
          report.routeLabel.toLowerCase().contains(q);
    }).toList();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _openReportSheet(SupportReport report) async {
    if (report.managerReadAt == null) {
      // Persist read-state so unread/bold works across sessions.
      await _service.markReportReadByManager(report.reportId);
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: NavigoColors.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(NavigoSizes.screenPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: NavigoColors.textMuted.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Report details', style: NavigoTextStyles.titleLarge),
                  const SizedBox(height: 12),
                  _detailRow('From', report.senderName),
                  _detailRow('Role', report.senderRole),
                  _detailRow('Route', report.routeLabel),
                  _detailRow('Date', _formatDate(report.createdAt)),
                  _detailRow('Status', report.status),
                  const SizedBox(height: 14),
                  Text('Message', style: NavigoTextStyles.titleSmall),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        report.message,
                        style: NavigoTextStyles.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: NavigoTextStyles.bodySmall.copyWith(
                color: NavigoColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              style: NavigoTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendToAdmin(List<SupportReport> visibleReports) async {
    final selectedReports = visibleReports
        .where((report) => selectedReportIds.contains(report.reportId))
        .toList();

    if (selectedReports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No reports selected!")),
      );
      return;
    }

    setState(() => _sending = true);

    try {
      await _service.sendReportsToAdmin(selectedReports);

      if (!mounted) return;

      setState(() {
        selectedReportIds.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Reports sent to admin successfully!")),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RouteSchedule()),
              ),
              context: context,
            ),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NavigoSizes.screenPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Reports", style: NavigoTextStyles.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    "Review and forward passenger and driver reports",
                    style: NavigoTextStyles.bodySmall,
                  ),
                ],
              ),
            ),

            const SizedBox(height: NavigoSizes.sectionGap),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NavigoSizes.screenPadding,
              ),
              child: TextField(
                controller: searchController,
                style: NavigoTextStyles.fieldText,
                decoration: NavigoDecorations.kInputDecoration.copyWith(
                  hintText: "Search reports...",
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
                onChanged: (value) {
                  setState(() => query = value);
                },
              ),
            ),

            const SizedBox(height: NavigoSizes.sectionGap),

            Expanded(
              child: StreamBuilder<List<SupportReport>>(
                stream: _service.watchReportsForCurrentRouteManager(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        "Failed to load reports",
                        style: NavigoTextStyles.bodyMedium,
                      ),
                    );
                  }

                  final reports = _filterReports(snapshot.data ?? []);

                  if (reports.isEmpty) {
                    return Center(
                      child: Text(
                        "No reports yet",
                        style: NavigoTextStyles.bodyMedium,
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NavigoSizes.screenPadding,
                    ),
                    itemCount: reports.length,
                    itemBuilder: (context, index) {
                      final report = reports[index];
                      final isSelected =
                          selectedReportIds.contains(report.reportId);
                      final isUnread = report.managerReadAt == null;
                      final titleStyle = NavigoTextStyles.titleSmall.copyWith(
                        fontWeight: isUnread ? FontWeight.w800 : FontWeight.w600,
                      );
                      final metaStyle = NavigoTextStyles.bodySmall.copyWith(
                        fontWeight: isUnread ? FontWeight.w700 : FontWeight.w400,
                      );
                      final chipTextStyle = NavigoTextStyles.bodySmall.copyWith(
                        color: NavigoColors.textLight,
                        fontWeight: isUnread ? FontWeight.w800 : FontWeight.w600,
                      );

                      return Container(
                        margin: const EdgeInsets.only(
                          bottom: NavigoSizes.itemGap,
                        ),
                        padding: const EdgeInsets.all(NavigoSizes.cardPadding),
                        decoration: NavigoDecorations.kCardDecoration,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: isSelected,
                              activeColor: NavigoColors.primaryOrange,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    selectedReportIds.add(report.reportId);
                                  } else {
                                    selectedReportIds.remove(report.reportId);
                                  }
                                });
                              },
                            ),

                            const SizedBox(width: 8),

                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _openReportSheet(report),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        report.senderName.isEmpty
                                            ? 'Unknown user'
                                            : report.senderName,
                                        style: titleStyle,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Role: ${report.senderRole}',
                                        style: metaStyle,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Route: ${report.routeLabel}',
                                        style: metaStyle,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),

                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: NavigoColors.accentGreen,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _formatDate(report.createdAt),
                                style: chipTextStyle,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(NavigoSizes.screenPadding),
              child: StreamBuilder<List<SupportReport>>(
                stream: _service.watchReportsForCurrentRouteManager(),
                builder: (context, snapshot) {
                  final visibleReports = _filterReports(snapshot.data ?? []);

                  return SizedBox(
                    width: double.infinity,
                    height: NavigoSizes.buttonHeight,
                    child: ElevatedButton(
                      onPressed: _sending
                          ? null
                          : () => _sendToAdmin(visibleReports),
                      style: NavigoDecorations.kPrimaryButtonLargeStyle,
                      child: _sending
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "Send to Admin",
                              style: NavigoTextStyles.button,
                            ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const RouteManagerNavBar(currentIndex: 2),
    );
  }
}