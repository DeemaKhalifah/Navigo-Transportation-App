import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

String? _nonEmptyRouteId(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  return s;
}

/// Resolves which route document the signed-in route manager manages.
///
/// Order:
/// 1. `users/{uid}.routeId`
/// 2. `route_manager/{uid}.routeId`
///
/// Returns `null` if not linked (caller shows UI hint).
Future<String?> resolveManagedRouteId() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;

  final firestore = FirebaseFirestore.instance;

  final userSnap = await firestore.collection('users').doc(uid).get();
  final fromUser = _nonEmptyRouteId(userSnap.data()?['routeId']);
  if (fromUser != null) return fromUser;

  final rmSnap = await firestore.collection('route_manager').doc(uid).get();
  return _nonEmptyRouteId(rmSnap.data()?['routeId']);
}
