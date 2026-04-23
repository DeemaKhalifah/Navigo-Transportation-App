import 'package:flutter/material.dart';
import 'package:navigo/screens/route_manager/route_schedule.dart';
import 'route_manager_nav_bar.dart';
import 'package:navigo/theme/app_theme.dart';

class Reports extends StatefulWidget {
  const Reports({super.key});

  @override
  State<Reports> createState() => _ReportsState();
}

class _ReportsState extends State<Reports> {
  final TextEditingController searchController = TextEditingController();

  final List<Map<String, String>> allReports = [
    {
      "from": "Lara Shaltal",
      "date": "28 Mar",
      "message":
          "The bus was overcrowded and the driver skipped my stop. Please look into this issue.",
    },
    {
      "from": "Omar Saleh",
      "date": "10 Mar",
      "message":
          "I faced a problem with the bus timing today. The trip was delayed for more than 30 minutes.",
    },
    {
      "from": "Ahmad Khaled",
      "date": "28 Jan",
      "message":
          "I would like to report that the bus arrived very late today and the driver did not follow the scheduled route.",
    },
  ];

  List<bool> selected = [];

  @override
  void initState() {
    super.initState();
    selected = List<bool>.filled(allReports.length, false);
  }

  List<Map<String, String>> get filteredReports {
    final query = searchController.text.toLowerCase();
    if (query.isEmpty) return allReports;
    return allReports.where((report) {
      return report["from"]!.toLowerCase().contains(query) ||
          report["date"]!.toLowerCase().contains(query);
    }).toList();
  }

  void sendToAdmin() {
    final selectedReports = <Map<String, String>>[];
    for (int i = 0; i < filteredReports.length; i++) {
      if (selected[i]) selectedReports.add(filteredReports[i]);
    }

    if (selectedReports.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No reports selected!")));
    } else {
      for (var report in selectedReports) {
        print("Sent report from ${report["from"]} to admin.");
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Reports sent to admin successfully!")),
      );
      setState(() {
        selected = List<bool>.filled(allReports.length, false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = filteredReports;

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,

      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// TOP BAR
            NavigoDecorations.topBar(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RouteSchedule()),
              ),
              context: context,
            ),

            /// TITLE
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
                    "Review and forward passenger reports",
                    style: NavigoTextStyles.bodySmall,
                  ),
                ],
              ),
            ),

            const SizedBox(height: NavigoSizes.sectionGap),

            /// SEARCH BOX
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NavigoSizes.screenPadding,
              ),
              child: TextField(
                controller: searchController,
                style: NavigoTextStyles.fieldText,
                decoration: NavigoDecorations.kInputDecoration.copyWith(
                  hintText: "Search by name or date...",
                  filled: true,
                  fillColor: NavigoColors.surfaceWhite,
                  prefixIcon: const Icon(
                    Icons.search,
                    color: NavigoColors.accentGreen, // ✅ green icon
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

            const SizedBox(height: NavigoSizes.sectionGap),

            /// REPORTS LIST — Expanded so it fills remaining space
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NavigoSizes.screenPadding,
                ),
                child: ListView.builder(
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final report = reports[index];

                    return Container(
                      margin: const EdgeInsets.only(
                        bottom: NavigoSizes.itemGap,
                      ),
                      padding: const EdgeInsets.all(NavigoSizes.cardPadding),
                      decoration: NavigoDecorations.kCardDecoration,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          /// CHECKBOX
                          Checkbox(
                            value: selected[index],
                            activeColor: NavigoColors.primaryOrange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            onChanged: (value) {
                              setState(() => selected[index] = value!);
                            },
                          ),

                          const SizedBox(width: 8),

                          /// REPORT CONTENT
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "From: ${report["from"]}",
                                  style: NavigoTextStyles.titleSmall,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  report["message"]!,
                                  style: NavigoTextStyles.bodyMedium,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          /// DATE CHIP
                          NavigoDecorations.statusChip(
                            label: report["date"]!,
                            color: NavigoColors.accentGreen,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            /// SEND BUTTON — pinned at bottom
            Padding(
              padding: const EdgeInsets.all(NavigoSizes.screenPadding),
              child: SizedBox(
                width: double.infinity,
                height: NavigoSizes.buttonHeight,
                child: ElevatedButton(
                  onPressed: sendToAdmin,
                  style: NavigoDecorations.kPrimaryButtonLargeStyle,
                  child: const Text(
                    "Send to Admin",
                    style: NavigoTextStyles.button,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: const RouteManagerNavBar(currentIndex: 2),
    );
  }
}
