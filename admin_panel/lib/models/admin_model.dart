class AdminModel {
  final String uid;
  final String email;
  final String role;

  AdminModel({required this.uid, required this.email, required this.role});

  factory AdminModel.fromMap(String uid, Map<String, dynamic> map) {
    return AdminModel(
      uid: uid,
      email: map['email'] ?? '',
      role: map['role'] ?? '',
    );
  }
}
