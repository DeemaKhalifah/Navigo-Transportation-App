import 'user.dart';
import 'driver.dart';
import 'passenger.dart';
import 'route_manager.dart';

class ReportModel {
  final String reportId;
  final UserModel sender; // Driver or Passenger
  final String description;
  final UserModel assignedTo; // Route Manager
  final DateTime time;
  final String status; // pending / in-progress / resolved

  ReportModel({
    required this.reportId,
    required this.sender,
    required this.description,
    required this.assignedTo,
    required this.time,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      "reportId": reportId,
      "sender": sender.toMap(),
      "description": description,
      "assignedTo": assignedTo.toMap(),
      "time": time.toIso8601String(),
      "status": status,
    };
  }

  factory ReportModel.fromMap(Map<String, dynamic> map) {
    return ReportModel(
      reportId: map["reportId"] ?? "",
      sender: _parseUser(map["sender"] ?? {}),
      description: map["description"] ?? "",
      assignedTo: _parseUser(map["assignedTo"] ?? {}),
      time: DateTime.parse(map["time"] ?? DateTime.now().toIso8601String()),
      status: map["status"] ?? "pending",
    );
  }

  /// Helper to parse a user map into the correct UserModel type
  static UserModel _parseUser(Map<String, dynamic> map) {
    switch (map["role"]) {
      case "driver":
      //return DriverModel.fromMap(map);
      case "passenger":
      //return Passenger.fromMap(map);
      case "route_manager":
        return RouteManagerModel.fromMap(map);
      default:
        throw UnsupportedError("Unknown role: ${map["role"]}");
    }
  }
}
