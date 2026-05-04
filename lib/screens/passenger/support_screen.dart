import 'package:flutter/material.dart';

import '../../controllers/support_report_controller.dart';
import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  late final SupportReportController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SupportReportController();
    _controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _submitComplaint() async {
    final error = await _controller.submit();
    if (!mounted) return;

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Complaint sent to route manager")),
      );
    } else if (error.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pop(context),
              context: context,
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    context.texts.t('helpSupportTitle'),
                    style: NavigoTextStyles.titleLarge,
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: NavigoDecorations.kCardDecoration,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.texts.t('supportSubtitle'),
                        style: NavigoTextStyles.titleSmall,
                      ),
                      const SizedBox(height: 10),

                      TextField(
                        controller: _controller.messageController,
                        maxLines: 6,
                        style: NavigoTextStyles.titleMedium,
                        decoration: NavigoDecorations.kInputDecoration.copyWith(
                          hintText: context.texts.t('writeComplaint'),
                        ),
                      ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _controller.isSending ? null : _submitComplaint,
                          style: NavigoDecorations.kPrimaryButtonLargeStyle,
                          child: _controller.isSending
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(context.texts.t('submit')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}