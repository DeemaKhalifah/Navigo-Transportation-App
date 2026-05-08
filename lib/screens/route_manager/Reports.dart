import 'package:flutter/material.dart';

import '../../localization/localization_x.dart';
import '../../models/support_report.dart';
import '../../services/support_report_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_message.dart';
import '../../widgets/responsive.dart';
import 'route_manager_notification_compose.dart';
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
    if (!report.isRead) {
      // Persist read-state so unread/bold works across sessions.
      await _service.markReportReadByManager(report.reportId);
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final media = MediaQuery.of(context);
        final padding = Responsive.horizontalPadding(context);

        return Container(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
          decoration: const BoxDecoration(
            color: NavigoColors.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.all(padding.clamp(16, 24)),
              child: Column(
                // The sheet has a max height; keeping the column bounded and
                // making only the message scroll avoids landscape overflows.
                mainAxisSize: MainAxisSize.max,
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
                  SizedBox(height: Responsive.verticalGap(context, 14)),
                  Text(
                    context.texts.t('reportDetails'),
                    style: NavigoTextStyles.titleLarge,
                  ),
                  SizedBox(height: Responsive.verticalGap(context, 12)),
                  _detailRow(context.texts.t('from'), report.senderName),
                  _detailRow(context.texts.t('role'), report.senderRole),
                  _detailRow(context.texts.t('route'), report.routeLabel),
                  _detailRow(
                    context.texts.t('date'),
                    _formatDate(report.createdAt),
                  ),
                  _detailRow(context.texts.t('status'), report.status),
                  SizedBox(height: Responsive.verticalGap(context, 14)),
                  Text(
                    context.texts.t('message'),
                    style: NavigoTextStyles.titleSmall,
                  ),
                  SizedBox(height: Responsive.verticalGap(context, 8)),
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
          ConstrainedBox(
            // The label column flexes a little for translated text instead of
            // forcing a fixed 72px width in landscape/small screens.
            constraints: const BoxConstraints(minWidth: 64, maxWidth: 110),
            child: Text(
              label,
              style: NavigoTextStyles.bodySmall.copyWith(
                color: NavigoColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: Responsive.verticalGap(context, 10)),
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

  Widget _buildSearchField() {
    return TextField(
      controller: searchController,
      style: NavigoTextStyles.fieldText,
      decoration: NavigoDecorations.kInputDecoration.copyWith(
        hintText: context.texts.t('searchReports'),
        filled: true,
        fillColor: NavigoColors.surfaceWhite,
        prefixIcon: const Icon(Icons.search, color: NavigoColors.accentGreen),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (value) {
        setState(() => query = value);
      },
    );
  }

  Future<void> _sendToAdmin(List<SupportReport> visibleReports) async {
    final selectedReports = visibleReports
        .where((report) => selectedReportIds.contains(report.reportId))
        .toList();

    if (selectedReports.isEmpty) {
      AppMessage.showError(context, context.texts.t('noReportsSelected'));
      return;
    }

    setState(() => _sending = true);

    try {
      await _service.sendReportsToAdmin(selectedReports);

      if (!mounted) return;

      setState(() {
        selectedReportIds.clear();
      });

      AppMessage.showSuccess(context, context.texts.t('reportsSentSuccess'));
    } catch (e) {
      if (!mounted) return;

      AppMessage.showError(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Widget _buildSendButton({
    required List<SupportReport> visibleReports,
    required bool compact,
    required double padding,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        compact ? 4 : Responsive.verticalGap(context, 8),
        0,
        compact ? 8 : padding,
      ),
      child: SizedBox(
        width: double.infinity,
        height: compact ? 44 : Responsive.buttonHeight(context),
        child: ElevatedButton(
          onPressed: _sending ? null : () => _sendToAdmin(visibleReports),
          style: NavigoDecorations.kPrimaryButtonLargeStyle,
          child: _sending
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(
                  context.texts.t('sendToAdmin'),
                  style: NavigoTextStyles.button,
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isShort = MediaQuery.sizeOf(context).height < 520;
    final compact = isLandscape || isShort;

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar3(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RouteSchedule()),
              ),
              onNotification: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RouteManagerNotificationCompose(),
                ),
              ),
            ),

            if (compact)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      flex: 2,
                      child: Text(
                        context.texts.t('reports'),
                        style: NavigoTextStyles.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: Responsive.verticalGap(context, 12)),
                    // Landscape has very little vertical space, so the search
                    // field moves beside the title instead of consuming another
                    // full row and causing a bottom overflow.
                    Expanded(flex: 3, child: _buildSearchField()),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.texts.t('reports'),
                      style: NavigoTextStyles.titleLarge,
                    ),
                    SizedBox(height: Responsive.verticalGap(context, 4)),
                    Text(
                      context.texts.t('reportsSubtitle'),
                      style: NavigoTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(height: Responsive.verticalGap(context, 14)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: _buildSearchField(),
              ),
            ],

            SizedBox(height: compact ? 6 : Responsive.verticalGap(context, 14)),

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
                        context.texts.t('failedToLoadReports'),
                        style: NavigoTextStyles.bodyMedium,
                      ),
                    );
                  }

                  final reports = _filterReports(snapshot.data ?? []);

                  if (reports.isEmpty) {
                    return Center(
                      child: Text(
                        context.texts.t('noReportsYet'),
                        style: NavigoTextStyles.bodyMedium,
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: padding,
                      vertical: Responsive.verticalGap(context, 2),
                    ),
                    // The action button is part of the scrollable content in
                    // compact/landscape layouts, so it never forces the outer
                    // Column to overflow by a few pixels.
                    itemCount: reports.length + 1,
                    itemBuilder: (context, index) {
                      if (index == reports.length) {
                        return _buildSendButton(
                          visibleReports: reports,
                          compact: compact,
                          padding: padding,
                        );
                      }

                      final report = reports[index];
                      final isSelected = selectedReportIds.contains(
                        report.reportId,
                      );
                      final isUnread = !report.isRead;
                      final titleStyle = NavigoTextStyles.titleSmall.copyWith(
                        fontWeight: isUnread
                            ? FontWeight.w800
                            : FontWeight.w600,
                      );
                      final metaStyle = NavigoTextStyles.bodySmall.copyWith(
                        fontWeight: isUnread
                            ? FontWeight.w700
                            : FontWeight.w400,
                      );
                      final chipTextStyle = NavigoTextStyles.bodySmall.copyWith(
                        color: NavigoColors.textLight,
                        fontWeight: isUnread
                            ? FontWeight.w800
                            : FontWeight.w600,
                      );

                      return Container(
                        margin: EdgeInsets.only(
                          bottom: Responsive.verticalGap(context, 10),
                        ),
                        padding: EdgeInsets.all(
                          padding.clamp(14, NavigoSizes.cardPadding),
                        ),
                        decoration: NavigoDecorations.kCardDecoration,
                        child: _ReportCardContent(
                          isCompact: isLandscape,
                          checkbox: Checkbox(
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
                          content: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _openReportSheet(report),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: Responsive.verticalGap(context, 6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    report.senderName.isEmpty
                                        ? context.texts.t('unknownUser')
                                        : report.senderName,
                                    style: titleStyle,
                                  ),
                                  SizedBox(
                                    height: Responsive.verticalGap(context, 4),
                                  ),
                                  Text(
                                    '${context.texts.t('role')}: ${report.senderRole}',
                                    style: metaStyle,
                                  ),
                                  SizedBox(
                                    height: Responsive.verticalGap(context, 4),
                                  ),
                                  Text(
                                    '${context.texts.t('route')}: ${report.routeLabel}',
                                    style: metaStyle,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          dateChip: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: Responsive.verticalGap(context, 10),
                              vertical: Responsive.verticalGap(context, 6),
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
                        ),
                      );
                    },
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

class _ReportCardContent extends StatelessWidget {
  const _ReportCardContent({
    required this.isCompact,
    required this.checkbox,
    required this.content,
    required this.dateChip,
  });

  final bool isCompact;
  final Widget checkbox;
  final Widget content;
  final Widget dateChip;

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              checkbox,
              const SizedBox(width: 8),
              Expanded(child: content),
            ],
          ),
          const SizedBox(height: 8),
          // In landscape the card stacks the date below the text, so narrow
          // heights/translated text do not force a horizontal overflow.
          Align(alignment: AlignmentDirectional.centerEnd, child: dateChip),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        checkbox,
        const SizedBox(width: 8),
        Expanded(child: content),
        const SizedBox(width: 8),
        Flexible(flex: 0, child: dateChip),
      ],
    );
  }
}
