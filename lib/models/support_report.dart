import 'package:cloud_firestore/cloud_firestore.dart';

class SupportReport {
  final String reportId;
  final String senderId;
  final String senderName;
  final String senderRole; // passenger / driver
  final String routeId;
  final String routeLabel;
  final String message;
  final String status; // pending / sent_to_admin
  final DateTime? createdAt;
  final DateTime? sentToAdminAt;
  final DateTime? managerReadAt;

  const SupportReport({
    required this.reportId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.routeId,
    required this.routeLabel,
    required this.message,
    required this.status,
    this.createdAt,
    this.sentToAdminAt,
    this.managerReadAt,
  });

  static const pending = 'pending';
  static const sentToAdmin = 'sent_to_admin';

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'routeId': routeId,
      'routeLabel': routeLabel,
      'message': message,
      'status': status,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
      if (sentToAdminAt != null) 'sentToAdminAt': Timestamp.fromDate(sentToAdminAt!),
      if (managerReadAt != null) 'managerReadAt': Timestamp.fromDate(managerReadAt!),
    };
  }

  factory SupportReport.fromDoc(DocumentSnapshot doc) {
    final data = Map<String, dynamic>.from(doc.data() as Map? ?? {});

    return SupportReport(
      reportId: doc.id,
      senderId: (data['senderId'] ?? '').toString(),
      senderName: (data['senderName'] ?? 'Unknown user').toString(),
      senderRole: (data['senderRole'] ?? '').toString(),
      routeId: (data['routeId'] ?? '').toString(),
      routeLabel: (data['routeLabel'] ?? '').toString(),
      message: (data['message'] ?? '').toString(),
      status: (data['status'] ?? pending).toString(),
      createdAt: _toDate(data['createdAt']),
      sentToAdminAt: _toDate(data['sentToAdminAt']),
      managerReadAt: _toDate(data['managerReadAt']),
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}