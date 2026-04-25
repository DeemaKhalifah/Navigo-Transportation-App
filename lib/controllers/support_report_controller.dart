import 'package:flutter/material.dart';

import '../services/support_report_service.dart';

/// Manages "Help & Support" report submission state (MVC controller).
/// UI should not call services directly.
class SupportReportController extends ChangeNotifier {
  SupportReportController({SupportReportService? service})
      : _service = service ?? SupportReportService();

  final SupportReportService _service;

  final TextEditingController messageController = TextEditingController();

  bool isSending = false;

  Future<String?> submit() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return 'Enter your complaint';
    if (isSending) return null;

    isSending = true;
    notifyListeners();

    try {
      await _service.createSupportReport(message: text);
      messageController.clear();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }
}

